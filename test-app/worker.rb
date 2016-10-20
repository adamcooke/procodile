trap("TERM", proc { $exit = 1; puts("Exiting..."); $stdout.flush })

puts "Working running on #{ENV['PORT']}"
$stdout.flush
count = 0
loop do
  count +=1
  sleep 2
  Process.exit(0) if $exit
end
