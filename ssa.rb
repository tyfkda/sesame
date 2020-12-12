
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
  attr_accessor :op, :dst, :opr1, :opr2

  def self.mov(dst, opr1)
    IR.new(:MOV, dst, opr1)
  end

  def self.add(dst, lhs, rhs)
    IR.new(:ADD, dst, lhs, rhs)
  end

  def self.ret(opr1)
    IR.new(:RET, nil, opr1)
  end

  def initialize(op, dst, opr1 = nil, opr2 = nil)
    @op = op
    @dst = dst
    @opr1 = opr1
    @opr2 = opr2
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
    "#{@op}  #{@dst&.inspect}#{@opr1 ? (@dst ? ', ' : '') + @opr1.inspect : ''}#{@opr2 ? ', ' + @opr2.inspect : ''}"
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

class SSA
  def initialize(bbs)
    @bbs = bbs
  end

  def analyze()
    make_ssa()
    propagate_const()
    trim()
  end

  def make_ssa()
    reg_gens = Hash.new()
    gen_regs = Hash.new {|h, k| h[k] = []}

    @bbs.each do |bb|
      bb.each do |ir|
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
    end
  end

  def propagate_const()
    slots = [:opr1, :opr2]
    const_regs = {}

    @bbs.each do |bb|
      bb.each do |ir|
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
end

def dump_bbs(bbs)
  bbs.each_with_index do |bb, ib|
    puts "### BB #{ib}"
    bb.each do |ir|
      puts "  #{ir.inspect}"
    end
  end
end

class VM
  def run(bbs)
    @regs = {}

    ib = 0
    ip = 0

    loop do
      if ip >= bbs[ib].length
        ip = 0
        ib += 1
        break if ib >= bbs.length
      end
      ir = bbs[ib][ip]

      case ir.op
      when :NOP
        # nop
      when :MOV
        dst = ir.dst
        @regs[dst] = value(ir.opr1)
      when :ADD
        dst = ir.dst
        @regs[dst] = value(ir.opr1) + value(ir.opr2)
      when :RET
        return value(ir.opr1)
      else
        $stderr.puts "Unknown: #{ir.inspect}"
        exit 1
      end
      ip += 1
    end
  end

  def value(v)
    if v.genreg?
      @regs[v]
    else
      v
    end
  end
end

BBS = [
  [
    IR::mov(:A, 1),
    IR::mov(:A, 2),
    IR::mov(:B, 3),
    IR::add(:C, :A, :B),
    IR::ret(:C),
  ],
]

dump_bbs(BBS)

ssa = SSA.new(BBS)
ssa.analyze()

puts "\nSSA result:"
dump_bbs(BBS)

vm = VM.new()
result = vm.run(BBS)
puts "\nresult=#{result}"
