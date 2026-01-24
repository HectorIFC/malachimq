# Compile test support modules before ExUnit starts
for support_file <- Path.wildcard("#{__DIR__}/support/**/*.ex") do
  Code.compile_file(support_file, __DIR__)
end

ExUnit.start()
