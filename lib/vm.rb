class VM
  def run(bbs)
    @regs = {}

    ib = 0
    ip = 0

    loop do
      while ip >= bbs[ib].length
        ip = 0
        ib += 1
        return nil if ib >= bbs.length
      end
      ir = bbs[ib][ip]
      ip += 1

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
