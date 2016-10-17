trap("TERM", proc { puts "Exiting..." ; sleep(2) ; Process.exit(0) })

puts "Web server running on port 5000. \n Isn't this nice?\n This is on multiple lines."
$stdout.flush
loop do
  puts "Something! #{Time.now.to_s}"
  $stdout.flush
  sleep 2
end
