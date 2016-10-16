trap("USR1", proc {
  puts "Restarting!"
  $stdout.flush
  pid = fork do
    exec("ruby cron.rb")
  end
  File.open(ENV['PID_FILE'], 'w') { |f| f.write(pid.to_s + "\n") }
  puts "Created new process with PID #{pid}"
  $stdout.flush
})

trap("TERM", proc {
  $stdout.flush
  Process.exit(1)
})

if ENV['DONE']
  puts "Killing original parent at #{Process.ppid}"
  Process.kill('TERM', Process.ppid)
end

ENV['DONE'] = '1'

puts "Cron running with PID #{Process.pid}"
$stdout.flush
sleep 60 while true
