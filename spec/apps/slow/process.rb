puts "This is #{ENV['PROC_NAME']}. It stops slowly."
trap('TERM') { sleep 10; Process.exit }

loop do
  sleep 1
end
