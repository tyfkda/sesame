require 'set'

class VReg
  attr_reader :sym
  attr_accessor :gen
  attr_reader :value

  def self.const(value)
    vreg = VReg.new(nil, nil, value: value)
  end

  def initialize(sym, gen, value: nil)
    @sym = sym
    @gen = gen
    @value = value
  end

  def const?()
    @value != nil
  end

  def not_const?()
    @value == nil
  end

  def <=>(other)
    self.inspect() <=> other.inspect()
  end

  def inspect
    if @value != nil
      "$#{@value.inspect}"
    elsif @gen
      "%#{@sym}:#{@gen}"
    else
      "%#{@sym}"
    end
  end
end

class Object
  def vreg?
    self.is_a?(VReg)
  end
end

class IR
  attr_accessor :op, :dst, :opr1, :opr2, :cond, :bb, :name, :args, :funcindex

  def self.mov(dst, opr1)
    IR.new(:MOV, dst, opr1)
  end

  def self.bop(kind, dst, lhs, rhs)
    IR.new(kind, dst, lhs, rhs)
  end

  def self.cmp(opr1, opr2)
    IR.new(:CMP, nil, opr1, opr2)
  end

  def self.jmp(cond, bb)
    IR.new(:JMP, cond: cond, bb: bb)
  end

  def self.result(opr1)
    IR.new(:RESULT, nil, opr1)
  end

  def self.call(dst, name, args)
    IR.new(:CALL, dst, name: name, args: args)
  end

  def self.defun(name, funcindex)
    IR.new(:DEFUN, nil, name: name, funcindex: funcindex)
  end

  def self.phi(dst, regs)
    IR.new(:PHI, dst, args: regs)
  end

  def initialize(op, dst = nil, opr1 = nil, opr2 = nil, cond: nil, bb: nil, name: nil, args: nil, funcindex: nil)
    @op = op
    @dst = dst
    @opr1 = opr1
    @opr2 = opr2
    @cond = cond
    @bb = bb
    @name = name
    @args = args
    @funcindex = funcindex
  end

  def clear()
    @op = :NOP
    @dst = @opr1 = @opr2 = @cond = @bb = @name = @args = @funcindex = nil
  end

  def nop?()
    @op == :NOP
  end

  def sorted_operands()
    order = [@opr1, @opr2]
    case @op
    when :ADD, :MUL
      order.sort! do |a, b|
        if a.not_const? != b.not_const?
          a.not_const? ? -1 : 1
        else
          a <=> b
        end
      end
    end
    order
  end

  def [](key)
    instance_variable_get("@#{key}")
  end

  def []=(key, val)
    instance_variable_set("@#{key}", val)
  end

  def inspect
    case @op
    when :DEFUN
      "DEFUN: #{@name} = \##{@funcindex}"
    when :JMP
      "J#{@cond || 'MP'}  #{@bb.index}"
    when :CALL
      "CALL  #{@dst.inspect} <= #{@name} [#{@args.map {|arg| arg.inspect}.join(', ')}]"
    when :PHI
      "PHI  #{@dst.inspect} <= #{@args}"
    else
      "#{@op}  #{@dst&.inspect}#{@opr1 ? (@dst ? ', ' : '') + @opr1.inspect : ''}#{@opr2 ? ', ' + @opr2.inspect : ''}"
    end
  end
end

class BB
  attr_reader :index
  attr_reader :irs
  attr_accessor :next_bb

  attr_reader :in_regs, :out_regs, :assigned_regs
  attr_reader :from_bbs, :to_bbs

  def initialize(index, irs = [])
    @index = index
    @irs = irs
    @next_bb = nil
    @in_regs = Hash.new()
    @out_regs = Hash.new()
    @assigned_regs = Set.new()
    @from_bbs = []
    @to_bbs = []
  end

  def set_next()
    to_bbs = []
    to_bbs.push(@next_bb) if @next_bb
    unless irs.empty?
      last = irs.last
      if last.op == :JMP
        unless last.cond
          to_bbs.clear()
        end
        to_bbs.push(last.bb)
      end
    end
    @to_bbs = to_bbs
  end

  def length()
    @irs.length
  end

  def [](key)
    @irs[key]
  end

  def delete_at(key)
    @irs.delete_at(key)
  end

  def put_phis(phis)
    @irs.prepend(*phis)
  end

  def clear_phis()
    @irs.each do |ir|
      next if ir.nop?
      break if ir.op != :PHI
      ir.clear()
    end
  end

  def insert_phi_movs(movs)
    return if movs.empty?
    pos = @irs.length
    if pos > 0 && @irs[pos - 1].op == :JMP
      pos -= 1
    end
    @irs.insert(pos, *movs)
  end

  def inspect()
    "BB\##{@index}"
  end

  def dump()
    puts "### BB #{@index}: " + [
      !@from_bbs.empty? && "from=#{@from_bbs.map{|b| b.index}.inspect}",
      !@to_bbs.empty? && "to=#{@to_bbs.map{|b| b.index}.inspect}",
      !@in_regs.empty? && "in=#{@in_regs.inspect}",
      !@out_regs.empty? && "out=#{@out_regs.inspect}",
    ].select {|s| s}.join(', ')

    @irs.each do |ir|
      puts "  #{ir.inspect}"
    end
  end
end

class BBContainer
  attr_accessor :bbs, :params

  def initialize(params)
    @params = params
    @bbs = []
    @const_regs = {}

    @vregs = Hash.new {|h, k| h[k] = []}
    @params&.each do |vreg|
      @vregs[vreg.sym].push(vreg)
    end
  end

  def optimize()
    analyze_flow()
    make_ssa()
    minimize_phi()
    propagate_const()
    remove_dead_expr()
    resolve_phi()
    trim()

    # 関数の引数を最初のレジスタに変更
    unless @bbs.empty? || !@params
      bb0 = @bbs.first
      @params.map! do |vreg|
        bb0.in_regs[vreg.sym]
      end
    end
  end

  def analyze_flow()
    @bbs.map! do |bb|
      bb.set_next()
      if bb.index > 0 && bb.from_bbs.empty?
        nil
      else
        bb.to_bbs.each do |nb|
          nb.from_bbs.push(bb)
        end
        bb
      end
    end.filter! {|bb| bb}

    reg_gens = Hash.new {|h, k| h[k] = 0}
    @bbs.each do |bb|
      bb.irs.each do |ir|
        vregs = [ir.opr1, ir.opr2]
        vregs.concat(ir.args) if ir.args
        vregs.filter! {|x| x&.not_const?}
        vregs.each do |vreg|
          unless bb.in_regs.has_key?(vreg.sym) || bb.assigned_regs.include?(vreg.sym)
            bb.in_regs[vreg.sym] = nil
          end
        end

        if ir.dst
          gen = reg_gens[ir.dst.sym]
          reg_gens[ir.dst.sym] += 1
          bb.assigned_regs.add(ir.dst.sym)
        end
      end
    end

    # Propagate in regs to previous BB.
    propagate = -> (sym, from_bbs) {
      from_bbs.each do |from|
        unless from.out_regs.has_key?(sym)
          from.out_regs[sym] = nil
        end
        unless from.assigned_regs.include?(sym) || from.in_regs.has_key?(sym)
          from.in_regs[sym] = nil
          propagate.call(sym, from.from_bbs)
        end
      end
    }
    @bbs.each do |bb|
      bb.in_regs.keys.each do |sym|
        propagate.call(sym, bb.from_bbs)
      end
    end
  end

  def make_ssa()
    @bbs.each do |bb|
      if bb.from_bbs.length == 1
        # 前のBBのレジスタを使い回す
        from_bb = bb.from_bbs.first
        bb.in_regs.keys.each do |sym|
          bb.in_regs[sym] = from_bb.out_regs[sym]
        end
      else
        bb.in_regs.keys.each do |sym|
          gen = @vregs[sym].length
          vreg = VReg.new(sym, gen)
          bb.in_regs[sym] = vreg
          @vregs[sym].push(vreg)
        end
      end

      curregs = bb.in_regs.clone()
      bb.irs.each do |ir|
        ir.opr1 = curregs[ir.opr1.sym] if ir.opr1&.not_const?
        ir.opr2 = curregs[ir.opr2.sym] if ir.opr2&.not_const?
        if ir.args
          ir.args.map! do |arg|
            arg.const? ? arg : curregs[arg.sym]
          end
        end
        if ir.dst&.not_const?
          vreg = ir.dst
          sym = vreg.sym
          if @vregs.has_key?(sym)
            gen = @vregs[sym].length
            ir.dst = vreg = VReg.new(sym, gen)
          else
            vreg.gen = gen = 0
          end
          curregs[sym] = vreg
          @vregs[sym].push(vreg)
        end
      end

      bb.out_regs.keys.each do |sym|
        bb.out_regs[sym] = curregs[sym]
      end
    end

    # Insert phi
    @bbs.each do |bb|
      next if bb.in_regs.empty?
      if bb.index == 0
        phis = bb.in_regs.map do |sym, vreg|
          param = @params.find {|p| p.sym == sym}
          IR::phi(@vregs[sym][vreg.gen], [param])
        end
      elsif bb.from_bbs.length > 1
        phis = bb.in_regs.map do |sym, vreg|
          incomings = bb.from_bbs.map do |from_bb|
            from_bb.out_regs[sym]
          end
          IR::phi(@vregs[sym][vreg.gen], incomings)
        end
      end
      bb.put_phis(phis)
    end
  end

  def minimize_phi()
    mappings = {}
    loop do
      mappings.clear()
      @bbs.each do |bb|
        bb.irs.each do |ir|
          next if ir.nop?
          break if ir.op != :PHI

          incomings = ir.args.filter {|arg| (mappings[arg] || arg) != ir.dst}.uniq
          if incomings.length == 1
            incoming = incomings.first
            mappings[ir.dst] = mappings[incoming] || incoming
            ir.clear()
          end
        end
      end

      break if mappings.empty?
      replace_regs(mappings)
    end
  end

  def propagate_const()
    computed = {}
    @bbs.each do |bb|
      bb.irs.each do |ir|
        ir.opr1 = @const_regs[ir.opr1] if @const_regs.has_key?(ir.opr1)
        ir.opr2 = @const_regs[ir.opr2] if @const_regs.has_key?(ir.opr2)
        ir.args&.each_with_index do |arg, i|
          ir.args[i] = @const_regs[arg] if @const_regs.has_key?(arg)
        end

        case ir.op
        when :MOV
          @const_regs[ir.dst] = ir.opr1
          ir.clear()
        when :ADD, :SUB, :MUL, :DIV, :MOD
          key = [ir.op, *ir.sorted_operands()]
          if ir.opr1.const? && ir.opr2.const?
            value = case ir.op
            when :ADD then ir.opr1.value + ir.opr2.value
            when :SUB then ir.opr1.value - ir.opr2.value
            when :MUL then ir.opr1.value * ir.opr2.value
            when :DIV then ir.opr1.value / ir.opr2.value
            when :MOD then ir.opr1.value % ir.opr2.value
            else error("Unhandled: #{ir}")
            end
            @const_regs[ir.dst] = VReg::const(value)
            ir.clear()
          elsif computed.has_key?(key)
            @const_regs[ir.dst] = computed[key].dst
            ir.clear()
          else
            computed[key] = ir
          end
        end
      end
    end
  end

  def remove_dead_expr()
    loop do
      again = false
      @const_regs.keys.each do |vreg|
        next if register_used?(vreg)
        @const_regs.delete(vreg)
      end

      @bbs.each do |bb|
        bb.irs.each do |ir|
          dst = ir.dst
          next unless dst
          next if register_used?(dst)

          if ir.op == :CALL
            ir.dst = nil
          else
            ir.clear()
          end
          if @const_regs.has_key?(dst)
            @const_regs.delete(dst)
          end
          again = true
        end
      end
      break unless again
    end
  end

  def register_used?(vreg)
    return true if @const_regs.has_value?(vreg)

    @bbs.each do |bb|
      return true if bb.in_regs[vreg.sym] == vreg || bb.out_regs[vreg.sym] == vreg
      bb.irs.each do |ir|
        if ir.opr1&.eql?(vreg) || ir.opr2&.eql?(vreg) || ir&.args&.any? {|arg| arg.eql?(vreg)}
          return true
        end
      end
    end
    false
  end

  def resolve_phi()
    @bbs.each do |bb|
      phis = {}
      while !bb.irs.empty? && (bb.irs.first.op == :PHI || bb.irs.first.op == :NOP)
        ir = bb.irs.shift
        if ir.op == :PHI
          phis[ir.dst.sym] = ir
        end
      end

      bb.from_bbs.each_with_index do |from_bb, from_index|
        movs = bb.in_regs.keys.map do |sym|
          dst_reg = bb.in_regs[sym]
          src_reg = phis.has_key?(sym) ? phis[sym].args[from_index] : from_bb.out_regs[sym]
          val = @const_regs[src_reg] || src_reg
          dst_reg != val ? IR::mov(dst_reg, val) : nil
        end.select {|ir| ir}
        from_bb.clear_phis()
        from_bb.insert_phi_movs(movs)
      end
    end
  end

  def replace_regs(mappings)
    @bbs.each do |bb|
      bb.in_regs.keys.each do |sym|
        bb.in_regs[sym] = mappings[bb.in_regs[sym]] if mappings.has_key?(bb.in_regs[sym])
      end
      bb.out_regs.keys.each do |sym|
        bb.out_regs[sym] = mappings[bb.out_regs[sym]] if mappings.has_key?(bb.out_regs[sym])
      end
      bb.irs.each do |ir|
        ir.dst = mappings[ir.dst] if mappings.has_key?(ir.dst)
        ir.opr1 = mappings[ir.opr1] if mappings.has_key?(ir.opr1)
        ir.opr2 = mappings[ir.opr2] if mappings.has_key?(ir.opr2)
        ir.args&.map! {|arg| mappings[arg] || arg}
      end
    end
  end

  def trim()
    @bbs.each do |bb|
      ip = 0
      while ip < bb.length
        ir = bb[ip]
        if ir.nop?
          bb.delete_at(ip)
        else
          ip += 1
        end
      end
    end
  end

  def dump()
    @bbs.each do |bb|
      bb.dump()
    end
  end
end
