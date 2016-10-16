trap("TERM", proc { Process.exit(0) })

puts "Web server running on port 5000"
$stdout.flush
loop do
  sleep 5
end
