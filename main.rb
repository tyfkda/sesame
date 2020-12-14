require './lib/compiler'
require './lib/vm'
require './runtime'

def main()
  global = {
    array_new: ->(n) { array_new(n) },
    array_get: ->(array, i) { array_get(array, i) },
    array_set: ->(array, i, value) { array_set(array, i, value) },
    puts: ->(x) { puts(x) },
  }
  compiler = Compiler.new(global, [])
  compiler.compile(ARGV[0])

  global.each do |k, v|
    next if v.is_a?(Proc)
    puts "=== #{k} #{v[0].inspect}"
    v[1].dump()
    puts ""
  end
  compiler.bbcon.dump()

  vm = VM.new(global, compiler.bbcon.bbs)
  vm.run()
end

if $0 == __FILE__
  main()
end
