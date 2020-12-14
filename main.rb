require './lib/compiler'
require './lib/vm'

def main()
  global = {}
  compiler = Compiler.new(global, [])
  compiler.compile(ARGV[0])

  global.each do |k, v|
    puts "=== #{k} #{v[0].inspect}"
    v[1].dump()
    puts ""
  end
  compiler.bbcon.dump()

  vm = VM.new(global, compiler.bbcon.bbs)
  result = vm.run()
  puts "result=#{result}"
end

if $0 == __FILE__
  main()
end
