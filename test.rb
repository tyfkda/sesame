require 'stringio'
require './lib/compiler'
require './lib/vm'
require './runtime'

def try(title, expected, input)
  print "#{title} => "
  sio = StringIO.new(input)

  global = {
    array_new: ->(n) { array_new(n) },
    array_get: ->(array, i) { array_get(array, i) },
    array_set: ->(array, i, value) { array_set(array, i, value) },
    puts: ->(x) { puts(x) },
  }

  compiler = Compiler.new(global, [])
  compiler.compile(sio)

  vm = VM.new(global, compiler.bbcon.bbs)
  actual = vm.run()

  if actual == expected
    puts 'OK'
  else
    $stderr.puts "NG: #{expected} expected, but got #{actual}"
    exit(1)
  end
end

try 'const', 123, 'return 123'
try 'funcall', 987, 'def foo(x) return x; end; return foo(987)'
try 'if t', 1, 'def foo(x) if x>0 then x=1; end; return x; end; return foo(10)'
try 'if f', -10, 'def foo(x) if x>0 then x=1; end; return x; end; return foo(-10)'
try 'if-else t', 1, 'def foo(x) if x>0 then x=1; else x=-1; end; return x; end; return foo(10)'
try 'if-else f', -1, 'def foo(x) if x>0 then x=1; else x=-1; end; return x; end; return foo(-10)'
try 'while', 55, 'def sum(x) acc=0; i=1; while i<=x do acc=acc+i; i=i+1; end; return acc; end; return sum(10)'
try 'break', 10, 'acc=0; i=1; while 1==1 do if i==5 then break; end; acc=acc+i; i=i+1; end; return acc'
try 'recursive', 55, 'def fib(n) if n<2 then return n; else return fib(n-1)+fib(n-2); end; end; return fib(10)'
