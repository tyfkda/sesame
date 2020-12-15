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
      "$#{@value.to_s}"
    else
      "%#{@sym}:#{@gen}"
    end
  end
end

class Object
  def vreg?
    self.is_a?(VReg)
  end
end

class IR
  attr_accessor :op, :dst, :opr1, :opr2, :cond, :bb, :funcname, :args

  def self.nop()
    IR.new(:NOP)
  end

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

  def self.ret()
    IR.new(:RET)
  end

  def self.call(dst, funcname, args)
    IR.new(:CALL, dst, funcname: funcname, args: args)
  end

  def self.phi(dst, regs)
    IR.new(:PHI, dst, args: regs)
  end

  def initialize(op, dst = nil, opr1 = nil, opr2 = nil, cond: nil, bb: nil, funcname: nil, args: nil)
    @op = op
    @dst = dst
    @opr1 = opr1
    @opr2 = opr2
    @cond = cond
    @bb = bb
    @funcname = funcname
    @args = args
  end

  def clear()
    @op = :NOP
    @dst = @opr1 = @opr2 = @cond = @bb = @funcname = @args = nil
  end

  def nop?()
    @op == :NOP
  end

  def sorted_operands()
    order = [@opr1, @opr2]
    case @op
    when :ADD, :SUB, :MUL, :DIV, :MOD
      order.sort! do |a, b|
        if a.vreg? != b.vreg?
          a.vreg? ? -1 : 1
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
    when :JMP
      "J#{@cond || 'MP'}  #{@bb.index}"
    when :CALL
      "CALL  #{@dst.inspect} <= #{@funcname} [#{@args.map {|arg| arg.inspect}.join(', ')}]"
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
  attr_reader :to_bbs, :from_bbs
  attr_reader :phis

  def initialize(index)
    @index = index
    @irs = []
    @next_bb = nil
    @in_regs = Hash.new()
    @out_regs = Hash.new()
    @assigned_regs = Hash.new()
    @from_bbs = []
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

  def insert_phi_resolver(dst_reg, src_reg)
    ir = @irs.find {|ir| ir.dst == src_reg}
    if ir
      ir.dst = dst_reg
      return true
    end

    pos = @irs.length
    if pos > 0 && @irs[pos - 1].op == :JMP
      pos -= 1
    end
    @irs.insert(pos, IR::mov(dst_reg, src_reg))
    return false
  end

  def replace_reg(src_reg, dst_reg)
    @irs.each do |ir|
      ir.dst = dst_reg if ir.dst == src_reg
      ir.opr1 = dst_reg if ir.opr1 == src_reg
      ir.opr2 = dst_reg if ir.opr2 == src_reg
      if ir.args
        ir.args.length.times do |i|
          ir.args[i] = dst_reg if ir.args[i] == src_reg
        end
      end
    end
  end

  def inspect()
    "BB\##{@index}"
  end

  def dump()
    puts "### BB #{@index}: " + [
      @to_bbs && "to=#{@to_bbs.map{|b| b.index}.inspect}",
      @from_bbs && "from=#{@from_bbs.map{|b| b.index}.inspect}",
      @in_regs && "in=#{@in_regs.inspect}",
      @out_regs && "out=#{@out_regs.inspect}",
    ].select {|s| s}.join(', ')

    @irs.each do |ir|
      puts "  #{ir.inspect}"
    end
  end
end

class BBContainer
  attr_accessor :bbs, :params

  def initialize(params, bbs)
    @params = params
    @bbs = bbs
    @const_regs = {}
    @computed = {}

    @vregs = Hash.new {|h, k| h[k] = []}
    @params.each do |vreg|
      @vregs[vreg.sym].push(vreg)
    end
  end

  def analyze()
    analyze_flow()
    make_ssa()
    propagate_const()
    remove_dead_expr()
    resolve_phi()
    trim()

    unless @bbs.empty?
      bb0 = @bbs.first
      @params.map! do |vreg|
        @vregs[vreg.sym][bb0.in_regs[vreg.sym]]
      end
    end
  end

  def analyze_flow()
    unless @bbs.empty?
      bb0 = @bbs.first
      @params.each do |vreg|
        bb0.in_regs[vreg.sym] = 0
        vreg = @vregs[vreg.sym][0]
      end
    end

    @bbs.each do |bb|
      bb.set_next()
      bb.to_bbs.each do |nb|
        nb.from_bbs.push(bb)
      end

      bb.irs.each do |ir|
        vregs = [ir.opr1, ir.opr2]
        vregs.concat(ir.args) if ir.args
        vregs.filter! {|x| x&.not_const?}
        vregs.each do |vreg|
          unless bb.in_regs.has_key?(vreg.sym) || bb.assigned_regs.has_key?(vreg.sym)
            bb.in_regs[vreg.sym] = nil
          end
        end

        if ir.dst && !bb.assigned_regs.has_key?(ir.dst.sym)
          bb.assigned_regs[ir.dst.sym] = nil
        end
      end
    end

    # Propagate in regs to previous BB.
    loop do
      cont = false
      @bbs.each do |bb|
        bb.to_bbs.each do |tobb|
          in_regs = tobb.in_regs
          in_regs.keys.each do |sym|
            unless bb.out_regs.has_key?(sym)
              bb.out_regs[sym] = nil
            end
            if bb.assigned_regs.has_key?(sym) || bb.in_regs.has_key?(sym)
              next
            end
            bb.in_regs[sym] = nil
            cont = true
          end
        end
      end
      break unless cont
    end
  end

  def make_ssa()
    @bbs.each do |bb|
      bb.in_regs.keys.each do |sym|
        gen = @vregs[sym].length
        bb.in_regs[sym] = gen
        @vregs[sym].push(VReg.new(sym, gen))
      end

      bb.irs.each do |ir|
        if ir.opr1&.not_const?
          ir.opr1 = @vregs[ir.opr1.sym][@vregs[ir.opr1.sym].length - 1]
        end
        if ir.opr2&.not_const?
          ir.opr2 = @vregs[ir.opr2.sym][@vregs[ir.opr2.sym].length - 1]
        end
        if ir.args
          ir.args.map! do |arg|
            arg.const? ? arg : @vregs[arg.sym][@vregs[arg.sym].length - 1]
          end
        end
        if ir.dst
          vreg = ir.dst
          sym = vreg.sym
          if @vregs.has_key?(sym)
            gen = @vregs[sym].length
            vreg = VReg.new(sym, gen)
            ir.dst = vreg
          else
            vreg.gen = gen = 0
          end
          @vregs[sym].push(vreg)
        end
      end

      bb.out_regs.keys.each do |vreg|
        bb.out_regs[vreg] = @vregs[vreg].length - 1
      end
    end

    # Insert phi
    @bbs.each do |bb|
      next if bb.in_regs.empty?
      phis = bb.in_regs.map do |sym, gen|
        incomings = bb.from_bbs.map do |from_bb|
          g = from_bb.out_regs[sym]
          @vregs[sym][g]
        end
        IR::phi(@vregs[sym][gen], incomings)
      end
      bb.irs.insert(0, *phis)
    end
  end

  def propagate_const()
    slots = [:opr1, :opr2]

    2.times do  # To apply @const_regs backward.
      @bbs.each do |bb|
        bb.irs.each do |ir|
          if !bb.in_regs.empty? && bb.from_bbs.length == 1
            from_bb = bb.from_bbs.first
            bb.in_regs.keys.each do |sym|
              src_gen = from_bb.out_regs[sym]
              dst_gen = bb.in_regs[sym]
              if src_gen != dst_gen
                src_reg = @vregs[sym][src_gen]
                dst_reg = @vregs[sym][dst_gen]
                @const_regs[dst_reg] = @const_regs[src_reg] || src_reg

                bb.in_regs[sym] = src_gen
              end
            end
          end

          slots.each do |slot|
            opr = ir[slot]
            if opr&.not_const? && @const_regs.has_key?(opr)
              ir[slot] = @const_regs[opr]
            end
          end
          if ir.args
            ir.args.length.times do |i|
              arg = ir.args[i]
              if arg.not_const? && @const_regs.has_key?(arg)
                ir.args[i] = @const_regs[arg]
              end
            end
          end

          case ir.op
          when :MOV
            @const_regs[ir.dst] = ir.opr1
            ir.clear()
          when :ADD, :SUB, :MUL, :DIV, :MOD
            key = [ir.op, *ir.sorted_operands()]
            if @computed.has_key?(key) && @computed[key].dst != ir.dst
              @const_regs[ir.dst] = @computed[key].dst
              ir.clear()
            elsif ir.opr1.const? && ir.opr2.const?
              case ir.op
              when :ADD
                value = ir.opr1.value + ir.opr2.value
              when :SUB
                value = ir.opr1.value - ir.opr2.value
              when :MUL
                value = ir.opr1.value * ir.opr2.value
              when :DIV
                value = ir.opr1.value / ir.opr2.value
              when :MOD
                value = ir.opr1.value % ir.opr2.value
              else
                error("Unhandled: #{ir}")
              end
              @const_regs[ir.dst] = VReg::const(value)
              ir.clear()
            else
              key = [ir.op, *ir.sorted_operands()]
              @computed[key] = ir
            end
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
      while !bb.irs.empty? && bb.irs.first.op == :PHI
        ir = bb.irs.shift
        dst_reg = ir.dst
        bb.from_bbs.each_with_index do |from_bb, ifb|
          src_reg = ir.args[ifb]
          if src_reg != dst_reg
            if from_bb.insert_phi_resolver(dst_reg, src_reg)
              # src is replaced to dst.
              from_bb.replace_reg(src_reg, dst_reg)
            end
          end
        end
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
