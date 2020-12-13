class VM
  def run(bbs)
    @regs = {}
    @flag = 0

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
      when :SUB
        dst = ir.dst
        @regs[dst] = value(ir.opr1) - value(ir.opr2)
      when :MUL
        dst = ir.dst
        @regs[dst] = value(ir.opr1) * value(ir.opr2)
      when :DIV
        dst = ir.dst
        @regs[dst] = value(ir.opr1) / value(ir.opr2)
      when :CMP
        @flag = value(ir.opr1) - value(ir.opr2)
      when :JMP
        jmp = case ir.cond
          when nil
            true
          when :<
            @flag < 0
          when :<=
            @flag <= 0
          when :>
            @flag > 0
          when :>=
            @flag >= 0
          else
            error("Unhandled cond: #{ir.cond.inspect}")
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
