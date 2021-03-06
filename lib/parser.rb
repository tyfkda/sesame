require 'ripper'

def error(result)
  $stderr.puts(result) if result
  caller.each do |c|
    $stderr.puts(c)
  end
  exit(1)
end

def assert(result)
  error(nil) unless result
end

def simplify_expr(expr)
  case expr[0]
  when :var_field, :var_ref
    case expr[1][0]
    when :@ident
      expr[1][1].to_sym
    else
      error("Unhandled expr: #{expr.inspect}")
    end
  when :@int
    expr[1].to_i
  when :paren
    assert(expr[1].length == 1)
    simplify_expr(expr[1].first)
  when :binary
    [expr[2],
      simplify_expr(expr[1]),
      simplify_expr(expr[3])]
  when :unary
    [expr[1],
      simplify_expr(expr[2])]
  when :method_add_arg
    assert(expr[1].first == :fcall && expr[1][1].first == :@ident &&
      expr[2].first == :arg_paren)
    args = expr[2][1]&.first == :args_add_block ? expr[2][1][1].map {|arg| simplify_expr(arg)} : []
    [:funcall, expr[1][1][1].intern,
      args]
  else
    error("Unhandled expr: #{expr.inspect}")
  end
end

def simplify_stmt(stmt)
  case stmt[0]
  when Array
    [:block,
      *stmt.map {|s| simplify_stmt(s)}]
  when :def
    if stmt[1].first == :@ident &&
        stmt[2].first == :paren && stmt[2][1].first == :params &&
        stmt[3].first == :bodystmt
      params = stmt[2][1][1] ? stmt[2][1][1].map {|param| assert(param[0] == :@ident); param[1].intern} : []
      [:defun, stmt[1][1].intern, params,
        simplify_stmt(stmt[3][1])]
    else
      error("Malformed defun: #{stmt.inspect}")
    end
  when :method_add_arg
    [:expr,
      simplify_expr(stmt)]
  when :assign
    [:expr,
      [:"=",
        simplify_expr(stmt[1]),
        simplify_expr(stmt[2])]]
  when :if
    [:if,
      simplify_expr(stmt[1]),
      simplify_stmt(stmt[2]),
      stmt[3] && stmt[3][0] == :else && simplify_stmt(stmt[3][1])]
  when :while
    [:while,
      simplify_expr(stmt[1]),
      simplify_stmt(stmt[2])]
  when :break
    [:break]
  when :return0
    [:return, nil]
  when :return
    [:return,
      simplify_expr(stmt[1][1][0])]
  else
    error("Unhandled stmt: #{stmt.inspect}")
  end
end

def parse(file)
  lines = file.read()
  ast = Ripper.sexp(lines)
  assert(ast.length == 2 && ast[0] == :program)
  simplify_stmt(ast[1])
end
