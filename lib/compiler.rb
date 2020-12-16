require_relative './parser'
require_relative './ir'

class Compiler
  def initialize
    @bbs = []
    @bbindex = 0
    @vreg_count = 0
    set_curbb(bb_new())
  end

  def compile(file)
    toplevel = parse(file)
    gen(toplevel)

    bbcon = BBContainer.new(@bbs)
    bbcon.analyze()
    bbcon
  end

  def gen(ast)
    gen_stmt(ast)
  end

  def gen_stmt(ast)
    case ast[0]
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

  def gen_if(ast)
    tbb = bb_split(@curbb)
    fbb = bb_split(tbb)
    gen_cond_jmp(ast[1], false, fbb)
    set_curbb(tbb)
    gen_stmt(ast[2])
    if ast[3]
      nbb = bb_split(fbb)
      @curbb.irs.push(IR::jmp(nil, nbb.index))
      set_curbb(fbb)
      gen_stmt(ast[3])
      set_curbb(nbb)
    else
      set_curbb(fbb)
    end
  end

  def gen_while(ast)
    loop_bb = bb_split(@curbb)
    cond_bb = bb_split(loop_bb)
    next_bb = bb_split(cond_bb)

    @curbb.irs.push(IR::jmp(nil, cond_bb.index))
    set_curbb(loop_bb)
    gen_stmt(ast[2])

    set_curbb(cond_bb)
    gen_cond_jmp(ast[1], true, loop_bb)

    set_curbb(next_bb)
  end

  def gen_cond_jmp(ast, tf, bb)
    assert(ast[0] == :expr)
    cond = ast[1]
    case cond[0]
    when :bop
      case cond[1]
      when :==, :<, :<=, :>, :>=
        ck = tf ? cond[1] : flip_cond(cond[1])
        ck = gen_compare_expr(ck, cond[2], cond[3])
        @curbb.irs.push(IR::jmp(ck, bb.index))
      else
        error("Unhandled gen_cond_jmp: #{ast.inspect}")
      end
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

  def bb_split(bb)
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
    when Symbol, Integer
      ast
    when Array
      case ast[0]
      when :expr
        gen_expr(ast[1])
      when :bop
        gen_bop(ast)
      else
        error("Unhandled gen_expr: #{ast.inspect}")
      end
    else
      error("Unhandled gen_expr: #{ast.inspect}")
    end
  end

  def gen_bop(ast)
    case ast[1]
    when :"="
      dst = gen_expr(ast[2])
      src = gen_expr(ast[3])
      @curbb.irs.push(IR::mov(dst, src))
      dst
    when :"+"
      lhs = gen_expr(ast[2])
      rhs = gen_expr(ast[3])
      dst = new_vreg()
      @curbb.irs.push(IR::add(dst, lhs, rhs))
      dst
    else
      error("Unhandled gen_bop: #{ast.inspect}")
    end
  end

  def new_vreg()
    @vreg_count += 1
    "~#{@vreg_count}".to_sym
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
