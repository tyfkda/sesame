require 'stringio'
require './lib/compiler'
require './lib/vm'

def try(title, expected, input)
  print "#{title} => "
  sio = StringIO.new(input)

  global = {}
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
try 'add', 23, 'a = 1; b = 22; return a + b'

try 'if t', 1, "
  x = 10
  if x > 0
    x = 1
  end
  return x"

try 'if f', 0, "
  x = 0
  if x > 0
    x = 1
  end
  return x"

try 'if-else t', 1, "
  x = 10
  if x > 0
    x = 1
  else
    x = 2
  end
  return x"

try 'if-else f', 2, "
  x = 0
  if x > 0
    x = 1
  else
    x = 2
  end
  return x"

try 'while', 55, "
  x = 10
  acc = 0
  i = 1
  while i <= x
    acc = acc + i
    i = i + 1
  end
  return acc"

try 'funcall', 987, "
  def foo(x)
    return x
  end
  return foo(987)"
