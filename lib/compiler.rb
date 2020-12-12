require_relative './parser'
require_relative './ir'

class Compiler
  attr_reader :bbcon_array, :bbcon

  def initialize(params = nil)
    @bbindex = 0
    @vars = {}
    @vreg_count = 0

    if params
      params.map! do |sym|
        @vars[sym] = VReg.new(sym, nil)
      end
    end

    @bbcon = BBContainer.new(params)
    set_curbb(bb_new())
    @ret_bb = bb_split()
    @break_bb = nil

    unless params  # Top compiler
      @bbcon_array = [@bbcon]
    end
  end

  def compile(file)
    ast = Parser.new(file).parse()
    compile_ast(ast)
  end

  def optimize()
    @bbcon_array.each do |bbcon|
      bbcon.optimize()
    end
  end

  def dump()
    @bbcon_array.each do |bbcon|
      bbcon.dump()
      puts ""
    end
  end

  def compile_ast(ast)
    gen(ast)
    set_curbb(@ret_bb)
  end

  def gen(ast)
    case ast
    when Integer
      VReg::const(ast)
    when Symbol
      @vars[ast] ||= VReg.new(ast, nil)
    when Array
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
      when :break
        gen_break(ast)
      when :return
        gen_return(ast)
      when :assign
        dst = gen(ast[1])
        src = gen(ast[2])
        @curbb.irs.push(IR::mov(dst, src))
        dst
      when :+, :-, :*, :/, :%
        lhs = gen(ast[1])
        rhs = gen(ast[2])
        dst = new_vreg()
        kind = case ast[0]
          when :+ then  :ADD
          when :- then  :SUB
          when :* then  :MUL
          when :/ then  :DIV
          when :% then  :MOD
        end
        @curbb.irs.push(IR::bop(kind, dst, lhs, rhs))
        dst
      when :-@  # Negate
        gen([:-, 0, ast[1]])
      when :funcall
        args = ast[2].map {|v| gen(v)}
        dst = new_vreg()
        @curbb.irs.push(IR::call(dst, ast[1], args))
        dst
      else
        error("Unhandled gen: #{ast.inspect}")
      end
    else
      error("Unhandled gen: #{ast.inspect}")
    end
  end

  def gen_defun(ast)
    funcname = ast[1]
    params = ast[2]
    body = ast[3]
    subcompiler = Compiler.new(params)
    subcompiler.compile_ast(body)

    @bbcon_array.push(subcompiler.bbcon)
    @curbb.irs.push(IR::defun(funcname, @bbcon_array.length - 1))
  end

  def gen_if(ast)
    tbb = bb_split()
    fbb = bb_split(tbb)
    gen_cond_jmp(ast[1], false, fbb)
    set_curbb(tbb)
    gen(ast[2])
    if ast[3]
      nbb = bb_split(fbb)
      @curbb.irs.push(IR::jmp(nil, nbb))
      set_curbb(fbb)
      gen(ast[3])
      set_curbb(nbb)
    else
      set_curbb(fbb)
    end
  end

  def gen_while(ast)
    cond_bb = bb_split()
    body_bb = bb_split(cond_bb)
    next_bb, save_break = push_break_bb(body_bb)

    set_curbb(cond_bb)
    gen_cond_jmp(ast[1], false, next_bb)

    set_curbb(body_bb)
    gen(ast[2])
    @curbb.irs.push(IR::jmp(nil, cond_bb))

    set_curbb(next_bb)
    pop_break_bb(save_break)
  end

  def push_break_bb(parent_bb)
    prev = @break_bb
    bb = bb_split(parent_bb)
    @break_bb = bb;
    return bb, prev
  end

  def pop_break_bb(save)
    @break_bb = save
  end

  def gen_break(ast)
    assert(@break_bb)
    bb = bb_split(@curbb)
    @curbb.irs.push(IR::jmp(nil, @break_bb))
    set_curbb(bb)
  end

  def gen_cond_jmp(cond, tf, bb)
    case cond[0]
    when :==, :!=, :<, :<=, :>, :>=
      ck = tf ? cond[0] : flip_cond(cond[0])
      l = gen(cond[1])
      r = gen(cond[2])
      @curbb.irs.push(IR::cmp(l, r))
      @curbb.irs.push(IR::jmp(ck, bb))
    else
      error("Unhandled gen_cond_jmp: #{ast.inspect}")
    end
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
    val = ast[1] && gen(ast[1])
    @curbb.irs.push(IR::result(val))
    @curbb.irs.push(IR::jmp(nil, @ret_bb))
  end

  def set_curbb(bb)
    @curbb = bb
    @bbcon.bbs.push(bb)
  end

  def new_vreg()
    @vreg_count += 1
    VReg.new("~#{@vreg_count}".to_sym, nil)
  end
end

def flip_cond(cond)
  case cond
    when :== then  :!=
    when :!= then  :==
    when :<  then  :>=
    when :<= then  :>
    when :>  then  :<=
    when :>= then  :<
    else error("Illegal cond: `#{cond}'")
  end
end
