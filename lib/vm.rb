class VM
  def initialize(env, bbs)
    @env = env
    @regs = {}
    @flag = 0
    @bbs = bbs
    @callstack = []

    @bb = @bbs[0]
    @ip = 0
  end

  def run()
    loop do
      while @ip >= @bb.length
        @ip = 0
        @bb = @bb.next_bb
        return unless @bb
      end
      ir = @bb[@ip]
      @ip += 1

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
      when :MOD
        dst = ir.dst
        @regs[dst] = value(ir.opr1) % value(ir.opr2)
      when :CMP
        @flag = value(ir.opr1) - value(ir.opr2)
      when :JMP
        jmp = case ir.cond
          when nil
            true
          when :==
            @flag == 0
          when :!=
            @flag != 0
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
          @bb = ir.bb
          @ip = 0
        end
      when :RET
        result = value(ir.opr1)
        if @callstack.empty?
          return result
        end
        set_ret(result)
      when :CALL
        set_call(ir.funcname, ir.args)
      else
        $stderr.puts "Unknown op: #{ir.inspect}"
        exit 1
      end
    end
  end

  def set_call(funcname, args)
    unless @env.has_key?(funcname)
      error("`#{funcname}' not exist")
    end
    func = @env[funcname]
    if func.is_a?(Proc)
      args = args.map {|arg| value(arg)}
      result = func.call(*args)
      call_ir = @bb[@ip - 1]
      @regs[call_ir.dst] = result
    else
      @callstack.push([@bbs, @bb, @ip, @regs])
      params = func[0]
      bbcon = func[1]
      @bbs = bbcon.bbs
      @bb = @bbs[0]
      @ip = 0

      new_regs = {}
      params.each_with_index do |sym, i|
        new_regs[sym] = value(args[i])
      end
      @regs = new_regs
    end
  end

  def set_ret(result)
    @bbs, @bb, @ip, @regs = @callstack.pop()
    call_ir = @bb[@ip - 1]
    @regs[call_ir.dst] = result
  end

  def value(v)
    if v.const?
      v.value
    else
      @regs[v]
    end
  end

  def set_funcall(func)
    params = func[0]
    body = func[1]
    # TODO: Set arguments
    run(body)
  end
end
