class GenReg
  attr_reader :sym, :gen

  def initialize(sym, gen)
    @sym = sym
    @gen = gen
  end

  def inspect
    "%#{@sym}:#{@gen}"
  end
end

class Object
  def sym?
    self.is_a?(Symbol)
  end

  def genreg?
    self.is_a?(GenReg)
  end
end

class IR
  attr_accessor :op, :dst, :opr1, :opr2, :cond, :regs

  def self.nop()
    IR.new(:NOP)
  end

  def self.mov(dst, opr1)
    IR.new(:MOV, dst, opr1)
  end

  def self.add(dst, lhs, rhs)
    IR.new(:ADD, dst, lhs, rhs)
  end

  def self.cmp(opr1, opr2)
    IR.new(:CMP, nil, opr1, opr2)
  end

  def self.jmp(cond, bbno)
    IR.new(:JMP, nil, bbno, cond: cond)
  end

  def self.ret(opr1)
    IR.new(:RET, nil, opr1)
  end

  def self.phi(dst, regs)
    IR.new(:PHI, dst, regs: regs)
  end

  def initialize(op, dst = nil, opr1 = nil, opr2 = nil, cond: nil, regs: nil)
    @op = op
    @dst = dst
    @opr1 = opr1
    @opr2 = opr2
    @cond = cond
    @regs = regs
  end

  def clear()
    @op = :NOP
    @dst = @opr1 = @opr2 = nil
  end

  def nop?()
    @op == :NOP
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
      "J#{@cond || 'MP'}  #{@opr1}"
    when :PHI
      "PHI  #{@dst.inspect} <= #{@regs}"
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

  def set_next(next_index)
    to_bbs = []
    to_bbs.push(next_index) if next_index
    unless irs.empty?
      last = irs.last
      if last.op == :JMP
        unless last.cond
          to_bbs.clear()
        end
        to_bbs.push(last.opr1)
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

  def insert_phis(phis)
    return if @irs.empty?
    pos = @irs.length
    if @irs[pos - 1].op == :JMP
      pos -= 1
    end
    @irs.insert(pos, *phis)
  end

  def dump()
    puts "### BB #{@index}: to=#{@to_bbs.inspect}, from=#{@from_bbs.inspect}, in=#{@in_regs.inspect}, out=#{@out_regs.inspect}"
    #puts "assign=#{@assigned_regs.inspect}"

    @irs.each do |ir|
      puts "  #{ir.inspect}"
    end
  end
end

class BBContainer
  attr_accessor :bbs

  def initialize(bbs)
    @bbs = bbs
    @const_regs = {}
  end

  def analyze()
    analyze_flow()
    make_ssa()
    propagate_const()
    resolve_phi()
    trim()
  end

  def analyze_flow()
    @bbs.each_with_index do |bb, ib|
      bb.set_next(ib + 1 < @bbs.length ? ib + 1 : nil)
      bb.to_bbs.each do |nb|
        @bbs[nb].from_bbs.push(ib)
      end

      bb.irs.each do |ir|
        syms = [ir.opr1, ir.opr2].filter {|x| x.sym?}
        syms.each do |sym|
          unless bb.in_regs.has_key?(sym) || bb.assigned_regs.has_key?(sym)
            bb.in_regs[sym] = nil
          end
        end

        if ir.dst && !bb.assigned_regs.has_key?(ir.dst)
          bb.assigned_regs[ir.dst] = nil
        end
      end
    end

    # Propagate in regs to previous BB.
    loop do
      cont = false
      @bbs.each do |bb|
        bb.to_bbs.each do |ni|
          in_regs = @bbs[ni].in_regs
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
    reg_gens = Hash.new()
    @gen_regs = Hash.new {|h, k| h[k] = []}

    @bbs.each do |bb|
      bb.in_regs.keys.each do |sym|
        gen = reg_gens[sym] += 1
        bb.in_regs[sym] = gen
        @gen_regs[sym].push(GenReg.new(sym, gen))
      end

      bb.irs.each do |ir|
        if ir.opr1.sym?
          ir.opr1 = @gen_regs[ir.opr1][reg_gens[ir.opr1]]
        end
        if ir.opr2.sym?
          ir.opr2 = @gen_regs[ir.opr2][reg_gens[ir.opr2]]
        end
        if ir.dst.sym?
          sym = ir.dst
          gen = reg_gens.has_key?(sym) ? reg_gens[sym] + 1 : 0
          reg_gens[sym] = gen
          @gen_regs[sym].push(ir.dst = GenReg.new(sym, gen))
        end
      end

      bb.out_regs.keys.each do |sym|
        bb.out_regs[sym] = reg_gens[sym]
      end
    end
  end

  def propagate_const()
    slots = [:opr1, :opr2]

    @bbs.each do |bb|
      bb.irs.each do |ir|
        if !bb.in_regs.empty? && bb.from_bbs.length == 1
          from_bb = @bbs[bb.from_bbs.first]
          bb.in_regs.keys.each do |sym|
            src_gen = from_bb.out_regs[sym]
            dst_gen = bb.in_regs[sym]
            if src_gen != dst_gen
              src_reg = @gen_regs[sym][src_gen]
              dst_reg = @gen_regs[sym][dst_gen]
              @const_regs[dst_reg] = @const_regs[src_reg] || src_reg

              bb.in_regs[sym] = src_gen
            end
          end
        end

        slots.each do |slot|
          if ir[slot].genreg? && @const_regs.has_key?(ir[slot])
            ir[slot] = @const_regs[ir[slot]]
          end
        end

        case ir.op
        when :MOV
          if !ir.opr1.genreg?
            @const_regs[ir.dst] = ir.opr1
            ir.clear()
          end
        when :ADD
          if !ir.opr1.genreg? && !ir.opr2.genreg?
            @const_regs[ir.dst] = ir.opr1 + ir.opr2
            ir.clear()
          end
        end
      end
    end
  end

  def resolve_phi()
    @bbs.each do |bb|
      bb.from_bbs.each do |from|
        left_in_regs = bb.in_regs.keys
        from_bb = @bbs[from]
        from_bb.irs.each do |ir|
          if ir.dst && bb.in_regs.has_key?(ir.dst.sym)
            sym = ir.dst.sym
            dst_reg = @gen_regs[sym][bb.in_regs[sym]]
            ir.dst = dst_reg
            left_in_regs.delete(sym)
          end
        end
        movs = left_in_regs.map do |sym|
          next unless bb.in_regs[sym]
          dst_reg = @gen_regs[sym][bb.in_regs[sym]]
          src_gen = from_bb.out_regs[sym]
          src_reg = @gen_regs[sym][src_gen]
          val = @const_regs[src_reg] || src_reg
          dst_reg != src_reg ? IR::mov(dst_reg, val) : IR::nop()
        end.select {|ir| ir && !ir.nop?}
        from_bb.insert_phis(movs)
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
