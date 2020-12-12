class VM
  def initialize(global, bbcon_array)
    @global = global
    @bbcon_array = bbcon_array
    @locals = {}
    @flag = 0
    @callstack = []

    @bbs = bbcon_array[0].bbs
    @bb = @bbs[0]
    @ip = 0
    @result = nil
  end

  def run()
    loop do
      while @ip >= @bb.length
        @ip = 0
        @bb = @bb.next_bb
        unless @bb
          return @result if @callstack.empty?
          pop_callstack(@result)
        end
      end
      ir = @bb[@ip]
      @ip += 1

      case ir.op
      when :NOP
        # nop
      when :MOV then  @locals[ir.dst] = value(ir.opr1)
      when :ADD then  @locals[ir.dst] = value(ir.opr1) + value(ir.opr2)
      when :SUB then  @locals[ir.dst] = value(ir.opr1) - value(ir.opr2)
      when :MUL then  @locals[ir.dst] = value(ir.opr1) * value(ir.opr2)
      when :DIV then  @locals[ir.dst] = value(ir.opr1) / value(ir.opr2)
      when :MOD then  @locals[ir.dst] = value(ir.opr1) % value(ir.opr2)
      when :CMP then  @flag = value(ir.opr1) - value(ir.opr2)
      when :JMP
        jmp = case ir.cond
          when nil then true
          when :== then  @flag == 0
          when :!= then  @flag != 0
          when :<  then  @flag < 0
          when :<= then  @flag <= 0
          when :>  then  @flag > 0
          when :>= then  @flag >= 0
          else error("Unhandled cond: #{ir.cond.inspect}")
        end
        if jmp
          @bb = ir.bb
          @ip = 0
        end
      when :RESULT
        @result = value(ir.opr1)
      when :CALL
        funcall(ir.name, ir.args, ir.dst)
      when :DEFUN
        bbcon = @bbcon_array[ir.funcindex]
        @global[ir.name] = [bbcon.params, bbcon]  # Function.
      when :SET_GLOBAL
      else
        $stderr.puts "Unknown op: #{ir.inspect}"
        exit 1
      end
    end
  end

  def funcall(funcname, args, dst)
    unless @global.has_key?(funcname)
      error("`#{funcname}' not exist")
    end
    func = @global[funcname]
    if func.is_a?(Proc)
      args = args.map {|arg| value(arg)}
      result = func.call(*args)
      @locals[dst] = result
    else
      bbcon = func[1]
      push_callstack(func[0], bbcon.bbs, args, dst)
    end
  end

  def push_callstack(params, bbs, args, dst)
    @callstack.push([@bbs, @bb, @ip, @locals, dst])

    @bbs = bbs
    @locals = params.zip(args).inject({}) do |h, pa|
      h[pa[0]] = value(pa[1])
      h
    end

    @bb = @bbs[0]
    @ip = 0
  end

  def pop_callstack(result)
    @bbs, @bb, @ip, @locals, dst = @callstack.pop()
    @locals[dst] = result
  end

  def value(v)
    if v.is_a?(Array)  # Function.
      return v
    end

    if v.const?
      v.value
    else
      raise "#{@bb.inspect}(#{@ip}): #{v.inspect} is not in local" unless @locals.has_key?(v)
      @locals[v]
    end
  end
end
