trap("TERM", proc { puts "Exiting..." ; $stdout.flush ; Process.exit(0) })

puts "Web server running on port 5000. \n Isn't this nice?\n This is on multiple lines."
$stdout.flush
puts "Root: #{ENV['APP_ROOT']}"
puts "PID file: #{ENV['PID_FILE']}"
puts "SMTP server: #{ENV['SMTP_HOSTNAME']}"
puts "SMTP user: #{ENV['SMTP_USERNAME']}"
loop do
  #puts "Something! #{Time.now.to_s}"
  $stdout.flush
  sleep 2
end
