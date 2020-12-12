require 'stringio'
require './lib/compiler'
require './lib/vm'
require './runtime'

def try(title, expected, input)
  print "#{title} => "
  sio = StringIO.new(input)

  compiler = Compiler.new()
  compiler.compile(sio)
  compiler.optimize()

  global = {
    array_new: ->(n) { array_new(n) },
    array_get: ->(array, i) { array_get(array, i) },
    array_set: ->(array, i, value) { array_set(array, i, value) },
  }
  vm = VM.new(global, compiler.bbcon_array)
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

try 'break', 10, "
  acc = 0
  i = 1
  while 1 == 1
    if i == 5
      break
    end
    acc = acc + i
    i = i + 1
  end
  return acc"

try 'funcall', 987, "
  def foo(x)
    return x
  end
  return foo(987)"

try 'recursive', 55, "
  def fib(n)
    if n < 2
      return n
    else
      return fib(n - 1) + fib(n - 2)
    end
  end
  return fib(10)"

try 'array', 25, "
  def sieve(n)
    array = array_new(n + 1)
    i = 2
    count = 0
    while i <= n
      if array_get(array, i) == 0
        count = count + 1
        j = i
        while j <= n
          array_set(array, j, 1)
          j = j + i
        end
      end
      i = i + 1
    end
    return count
  end
  return sieve(100)"
