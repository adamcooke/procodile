trap("TERM", proc { $exit = 1; puts("Exiting..."); $stdout.flush })

puts "Working running"
$stdout.flush
loop do
  sleep 2
  Process.exit(0) if $exit
end
