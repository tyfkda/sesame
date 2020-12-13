require './lib/compiler'
require './lib/vm'

compiler = Compiler.new()
bbcon = compiler.compile(ARGV[0])
bbcon.dump()

vm = VM.new()
result = vm.run(bbcon.bbs)
puts "result=#{result}"
