puts "This is #{ENV['PROC_NAME']}"
trap('TERM') { Process.exit }
loop do
  sleep 1
end
