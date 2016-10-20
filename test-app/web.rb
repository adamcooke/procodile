trap("TERM", proc { puts "Exiting..." ; $stdout.flush ; Process.exit(0) })

puts "Web server running on port 5000. \n Isn't this nice?\n This is on multiple lines."
$stdout.flush
puts "Root: #{ENV['APP_ROOT']}"
puts "PID file: #{ENV['PID_FILE']}"
puts "SMTP server: #{ENV['SMTP_HOSTNAME']}"
puts "SMTP user: #{ENV['SMTP_USERNAME']}"
puts "Port: #{ENV['PORT']}"
$stdout.flush
require 'socket'
server = TCPServer.new('127.0.0.1', ENV['PORT'] || 5000)
loop do
  io = IO.select([server], nil, nil, 0.5)
  if io && io.first
    io.first.each do |fd|
      if client = fd.accept
        puts "Connection from #{client.addr[3]}"
        $stdout.flush
        client.puts "Hello"
        if data = client.gets
          client.puts "you sent: #{data}"
        end
        puts "Closed connection"
        $stdout.flush
        client.close
      end
    end
  end
end
