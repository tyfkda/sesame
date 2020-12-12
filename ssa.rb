class GenReg
  def initialize(sym, gen)
    @sym = sym
    @gen = gen
  end

  def inspect
    "%#{@sym}#{@gen}"
  end
end

class IR
  attr_accessor :op, :dst, :opr1, :opr2, :cond

  def self.mov(dst, opr1)
    IR.new(:MOV, dst, opr1)
  end

  def self.add(dst, lhs, rhs)
    IR.new(:ADD, dst, lhs, rhs)
  end

  def self.cmp(opr1, opr2)
    IR.new(:CMP, nil, opr1, opr2)
  end

  def self.jmp(bbno)
    IR.new(:JMP, nil, bbno)
  end

  def self.jgt(bbno)
    IR.new(:JMP, nil, bbno, cond: :GT)
  end

  def self.ret(opr1)
    IR.new(:RET, nil, opr1)
  end

  def initialize(op, dst, opr1 = nil, opr2 = nil, cond: nil)
    @op = op
    @dst = dst
    @opr1 = opr1
    @opr2 = opr2
    @cond = cond
  end

  def nop()
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
    if @op == :JMP
      "J#{@cond || 'MP'} #{@opr1}"
    else
      "#{@op}  #{@dst&.inspect}#{@opr1 ? (@dst ? ', ' : '') + @opr1.inspect : ''}#{@opr2 ? ', ' + @opr2.inspect : ''}"
    end
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

class BB
  attr_reader :irs
  attr_reader :in_regs, :out_regs, :assigned_regs
  attr_reader :next_bbs

  def initialize(irs)
    @irs = irs
    @in_regs = Hash.new()
    @out_regs = Hash.new()
    @assigned_regs = Hash.new()
  end

  def set_next(next_index)
    next_bbs = []
    next_bbs.push(next_index) if next_index
    unless irs.empty?
      last = irs.last
      if last.op == :JMP
        unless last.cond
          next_bbs.clear()
        end
        next_bbs.push(last.opr1)
      end
    end
    @next_bbs = next_bbs
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

  def dump(ib)
    puts "### BB #{ib}: next=#{@next_bbs.inspect}, in=#{@in_regs.inspect}, out=#{@out_regs.inspect}"
    #puts "assign=#{@assigned_regs.inspect}"

    @irs.each do |ir|
      puts "  #{ir.inspect}"
    end
  end
end

class BBContainer
  def initialize(bbs)
    @bbs = bbs
  end

  def analyze()
    analyze_flow()
    make_ssa()
    #propagate_const()
    #trim()
  end

  def analyze_flow()
    @bbs.each_with_index do |bb, ib|
      bb.set_next(ib + 1 < @bbs.length ? ib + 1 : nil)
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
        bb.next_bbs.each do |ni|
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
    gen_regs = Hash.new {|h, k| h[k] = []}

    @bbs.each do |bb|
      bb.in_regs.keys.each do |sym|
        gen = reg_gens[sym] += 1
        bb.in_regs[sym] = gen
        gen_regs[sym].push(GenReg.new(sym, gen))
      end

      bb.irs.each do |ir|
        if ir.opr1.sym?
          ir.opr1 = gen_regs[ir.opr1][reg_gens[ir.opr1]]
        end
        if ir.opr2.sym?
          ir.opr2 = gen_regs[ir.opr2][reg_gens[ir.opr2]]
        end
        if ir.dst.sym?
          sym = ir.dst
          gen = reg_gens.has_key?(sym) ? reg_gens[sym] + 1 : 0
          reg_gens[sym] = gen
          gen_regs[sym].push(ir.dst = GenReg.new(sym, gen))
        end
      end

      bb.out_regs.keys.each do |sym|
        bb.out_regs[sym] = reg_gens[sym]
      end
    end
  end

  def propagate_const()
    slots = [:opr1, :opr2]
    const_regs = {}

    @bbs.each do |bb|
      bb.irs.each do |ir|
        slots.each do |slot|
          if ir[slot].genreg? && const_regs.has_key?(ir[slot])
            ir[slot] = const_regs[ir[slot]]
          end
        end

        case ir.op
        when :MOV
          if !ir.opr1.genreg?
            const_regs[ir.dst] = ir.opr1
            ir.nop()
          end
        when :ADD
          if !ir.opr1.genreg? && !ir.opr2.genreg?
            const_regs[ir.dst] = ir.opr1 + ir.opr2
            ir.nop()
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
    @bbs.each_with_index do |bb, ib|
      bb.dump(ib)
    end
  end
end

class VM
  def run(bbs)
    @regs = {}
    @flag = 0

    ib = 0
    ip = 0

    loop do
      if ip >= bbs[ib].length
        ip = 0
        ib += 1
        break if ib >= bbs.length
      end
      ir = bbs[ib][ip]
      ip +=1

      case ir.op
      when :NOP
        # nop
      when :MOV
        dst = ir.dst
        @regs[dst] = value(ir.opr1)
      when :ADD
        dst = ir.dst
        @regs[dst] = value(ir.opr1) + value(ir.opr2)
      when :CMP
        @flag = value(ir.opr1) - value(ir.opr2)
      when :JMP
        jmp = case ir.cond
              when :GT
                @flag > 0
              else
                true
              end
        if jmp
          ib = ir.opr1
          ip = 0
        end
      when :RET
        return value(ir.opr1)
      else
        $stderr.puts "Unknown: #{ir.inspect}"
        exit 1
      end
    end
  end

  def value(v)
    if v.genreg? || v.sym?
      @regs[v]
    else
      v
    end
  end
end

BBS = [
  BB.new([
      IR::mov(:A, 0),
      IR::mov(:I, 1),
    ]),
  BB.new([
      IR::cmp(:I, 10),
      IR::jgt(3),
    ]),
  BB.new([
      IR::add(:A, :A, :I),
      IR::add(:I, :I, 1),
      IR::jmp(1),
    ]),
  BB.new([
      IR::ret(:A),
    ]),
]

bbs = BBContainer.new(BBS)
#bbs.dump()
bbs.analyze()
bbs.dump()

#vm = VM.new()
#result = vm.run(BBS)
#puts "\nresult=#{result}"
