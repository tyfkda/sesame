require 'stringio'
require './lib/compiler'
require './lib/vm'

def try(title, expected, input)
  print "#{title} => "
  sio = StringIO.new(input)

  compiler = Compiler.new()
  bbcon = compiler.compile(sio)

  vm = VM.new()
  actual = vm.run(bbcon.bbs)

  if actual == expected
    puts 'OK'
  else
    $stderr.puts "NG: #{expected} expected, but got #{actual}"
    exit(1)
  end
end

try 'const', 123, 'return 123'
try 'add', 23, 'a = 1; b = 22; return a + b'
