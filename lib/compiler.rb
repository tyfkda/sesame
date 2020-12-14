require_relative './parser'
require_relative './ir'

class Compiler
  attr_reader :bbcon

  def initialize(env, params)
    @env = env
    @bbs = []
    @bbindex = 0
    @vars = {}
    @vreg_count = 0

    params.map! do |sym|
      @vars[sym] = VReg.new(sym, nil)
    end

    @bbcon = BBContainer.new(params, @bbs)
    set_curbb(bb_new())
  end

  def compile(file)
    toplevel = parse(file)
    compile_ast(toplevel)
  end

  def compile_ast(ast)
    gen(ast)
    @bbcon.analyze()
  end

  def gen(ast)
    gen_stmt(ast)
  end

  def gen_stmt(ast)
    case ast[0]
    when :defun
      gen_defun(ast)
    when :block
      ast.slice(1..).map do |sub|
        gen(sub)
      end
    when :if
      gen_if(ast)
    when :while
      gen_while(ast)
    when :return
      gen_return(ast)
    when :expr
      gen_expr(ast[1])
    else
      error("Unhandled gen: #{ast.inspect}")
    end
  end

  def gen_defun(ast)
    funcname = ast[1]
    params = ast[2]
    subcompiler = Compiler.new(@env, params)
    subcompiler.compile_ast(ast[3])
    register_global(funcname, gen_func(subcompiler))
  end

  def gen_func(subcompiler)
    [subcompiler.bbcon.params, subcompiler.bbcon]
  end

  def register_global(symbol, value)
    @env[symbol] = value
  end

  def gen_if(ast)
    tbb = bb_split()
    fbb = bb_split(tbb)
    gen_cond_jmp(ast[1], false, fbb)
    set_curbb(tbb)
    gen_stmt(ast[2])
    if ast[3]
      nbb = bb_split(fbb)
      @curbb.irs.push(IR::jmp(nil, nbb))
      set_curbb(fbb)
      gen_stmt(ast[3])
      set_curbb(nbb)
    else
      set_curbb(fbb)
    end
  end

  def gen_while(ast)
    cond_bb = bb_split()
    body_bb = bb_split(cond_bb)
    next_bb = bb_split(body_bb)

    set_curbb(cond_bb)
    gen_cond_jmp(ast[1], false, next_bb)

    set_curbb(body_bb)
    gen_stmt(ast[2])
    @curbb.irs.push(IR::jmp(nil, cond_bb))

    set_curbb(next_bb)
  end

  def gen_cond_jmp(ast, tf, bb)
    cond = ast
    case cond[0]
    when :==, :!=, :<, :<=, :>, :>=
      ck = tf ? cond[0] : flip_cond(cond[0])
      ck = gen_compare_expr(ck, cond[1], cond[2])
      @curbb.irs.push(IR::jmp(ck, bb))
    else
      error("Unhandled gen_cond_jmp: #{ast.inspect}")
    end
  end

  def gen_compare_expr(c, lhs, rhs)
    l = gen_expr(lhs)
    r = gen_expr(rhs)
    @curbb.irs.push(IR::cmp(l, r))
    c
  end

  def bb_new()
    index = @bbindex
    @bbindex += 1
    BB::new(index)
  end

  def bb_split(bb = @curbb)
    cc = bb_new()
    cc.next_bb = bb.next_bb
    bb.next_bb = cc
    cc
  end

  def gen_return(ast)
    val = ast[1] && gen_expr(ast[1])
    @curbb.irs.push(IR::ret(val))
  end

  def set_curbb(bb)
    @curbb = bb
    @bbs.push(bb)
  end

  def gen_expr(ast)
    case ast
    when Integer
      VReg::const(ast)
    when Symbol
      @vars[ast] ||= VReg.new(ast, nil)
    when Array
      case ast[0]
      when :"="
        dst = gen_expr(ast[1])
        src = gen_expr(ast[2])
        @curbb.irs.push(IR::mov(dst, src))
        dst
      when :+, :-, :*, :/, :%
        lhs = gen_expr(ast[1])
        rhs = gen_expr(ast[2])
        dst = new_vreg()
        case ast[0]
        when :+
          kind = :ADD
        when :-
          kind = :SUB
        when :*
          kind = :MUL
        when :/
          kind = :DIV
        when :%
          kind = :MOD
        end
        @curbb.irs.push(IR::bop(kind, dst, lhs, rhs))
        dst
      when :-@  # Negate
        gen_expr([:-, 0, ast[1]])
      when :funcall
        args = ast[2].map {|v| gen_expr(v)}
        dst = new_vreg()
        @curbb.irs.push(IR::call(dst, ast[1], args))
        dst
      else
        error("Unhandled gen_expr: #{ast.inspect}")
      end
    else
      error("Unhandled gen_expr: #{ast.inspect}")
    end
  end

  def new_vreg()
    @vreg_count += 1
    VReg.new("~#{@vreg_count}".to_sym, nil)
  end
end

def flip_cond(cond)
  case cond
  when :==
    :!=
  when :!=
    :==
  when :<
    :>=
  when :<=
    :>
  when :>
    :<=
  when :>=
    :<
  else
    error("Illegal cond: `#{cond}'")
  end
end
