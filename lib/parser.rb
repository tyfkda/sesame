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

class Parser
  def initialize(file)
    @file = file
  end

  def parse()
    lines = @file.read()
    ast = Ripper.sexp(lines)
    if ast
      assert(ast.instance_of?(Array) && ast[0] == :program)
      simplify(ast)
    end
  end

  def simplify(ast)
    case ast[0]
    when Array
      [:block,
        *ast.map {|s| simplify(s)}]
    when :program
      assert(ast.length == 2)
      simplify(ast[1])
    when :def
      if ast[1].first == :@ident &&
          ast[2].first == :paren && ast[2][1].first == :params &&
          ast[3].first == :bodystmt
        params = ast[2][1][1] ? ast[2][1][1].map {|param| assert(param[0] == :@ident); param[1].intern} : []
        [:defun, ast[1][1].intern, params,
          simplify(ast[3][1])]
      else
        error("Malformed defun: #{ast.inspect}")
      end
    when :method_add_arg
      assert(ast[1].first == :fcall && ast[1][1].first == :@ident &&
             ast[2].first == :arg_paren)
      args = ast[2][1]&.first == :args_add_block ? ast[2][1][1].map {|arg| simplify(arg)} : []
      [:funcall, ast[1][1][1].intern,
        args]
    when :if
      [:if,
        simplify(ast[1]),
        simplify(ast[2]),
        ast[3] && ast[3][0] == :else && simplify(ast[3][1])]
    when :while
      [:while,
        simplify(ast[1]),
        simplify(ast[2])]
    when :break
      [:break]
    when :return0
      [:return, nil]
    when :return
      [:return,
        simplify(ast[1][1][0])]
    when :var_field, :var_ref
      assert(ast[1][0] == :@ident)
      ast[1][1].to_sym
    when :@int
      ast[1].to_i
    when :paren
      assert(ast[1].length == 1)
      simplify(ast[1].first)
    when :binary
      [ast[2],
        simplify(ast[1]),
        simplify(ast[3])]
    when :unary
      [ast[1],
        simplify(ast[2])]
    when :assign
      [:assign,
        simplify(ast[1]),
        simplify(ast[2])]
    else
      error("Unhandled ast: #{ast.inspect}")
    end
  end
end
