require 'fileutils'
require 'procodile/error'
require 'procodile/supervisor'
require 'procodile/signal_handler'
require 'procodile/control_client'

module Procodile
  class CLI

    def initialize(config, cli_options = {})
      @config = config
      @cli_options = cli_options
    end

    def run(command)
      if self.class.instance_methods(false).include?(command.to_sym) && command != 'run'
        public_send(command)
      else
        raise Error, "Invalid command '#{command}'"
      end
    end

    def start
      if running?
        instances = ControlClient.run(@config.sock_path, 'start_processes', :processes => process_names_from_cli_option)
        if instances.empty?
          raise Error, "No processes were started. The type you entered might already be running or isn't defined."
        else
          instances.each do |instance|
            puts "Started #{instance['description']} (PID: #{instance['pid']})"
          end
          return
        end
      end

      run_options = {}
      run_options[:brittle] = @cli_options[:brittle]

      processes = process_names_from_cli_option

      if @cli_options[:clean]
        FileUtils.rm_f(File.join(@config.pid_root, '*.pid'))
        FileUtils.rm_f(File.join(@config.pid_root, '*.sock'))
        puts "Removed all old pid & sock files"
      end

      if @cli_options[:foreground]
        File.open(pid_path, 'w') { |f| f.write(::Process.pid) }
        Supervisor.new(@config, run_options).start(:processes => processes)
      else
        FileUtils.rm_f(File.join(@config.pid_root, "*.pid"))
        pid = fork do
          STDOUT.reopen(@config.log_path, 'a')
          STDOUT.sync = true
          STDERR.reopen(@config.log_path, 'a')
          STDERR.sync = true
          Supervisor.new(@config, run_options).start(:processes => processes)
        end
        ::Process.detach(pid)
        File.open(pid_path, 'w') { |f| f.write(pid) }
        puts "Started #{@config.app_name} supervisor with PID #{pid}"
      end
    end

    def stop
      if running?
        options = {}
        instances = ControlClient.run(@config.sock_path, 'stop', :processes => process_names_from_cli_option)
        if instances.empty?
          puts "There are no processes to stop."
        else
          instances.each do |instance|
            puts "Stopping #{instance['description']} (PID: #{instance['pid']})"
          end
        end
      else
        raise Error, "#{@config.app_name} supervisor isn't running"
      end
    end

    def restart
      if running?
        options = {}
        instances = ControlClient.run(@config.sock_path, 'restart', :processes => process_names_from_cli_option)
        if instances.empty?
          puts "There are no processes to restart."
        else
          instances.each do |instance|
            puts "Restarting #{instance['description']} (PID: #{instance['pid']})"
          end
        end
      else
        raise Error, "#{@config.app_name} supervisor isn't running"
      end
    end

    def stop_supervisor
      if running?
        ::Process.kill('TERM', current_pid)
        puts "Supervisor will be stopped in a moment."
      else
        raise Error, "#{@config.app_name} supervisor isn't running"
      end
    end

    def reload_config
      if running?
        ControlClient.run(@config.sock_path, 'reload_config')
        puts "Reloading config for #{@config.app_name}"
      else
        raise Error, "#{@config.app_name} supervisor isn't running"
      end
    end

    def status
      if running?
        stats = ControlClient.run(@config.sock_path, 'status')
        if @cli_options[:json]
          puts stats.to_json
        else
          puts "|| supervisor pid #{stats['supervisor']['pid']}"
          if time = stats['supervisor']['started_at']
            time = Time.at(time)
            puts "|| supervisor started at #{time.to_s}"
          end
          puts

          stats['processes'].each_with_index do |process, index|
            puts unless index == 0
            puts "|| ".color(process['log_color']) + process['name'].color(process['log_color'])
            puts "||".color(process['log_color']) + " Quantity            " + process['quantity'].to_s
            puts "||".color(process['log_color']) + " Command             " + process['command']
            puts "||".color(process['log_color']) + " Respawning          " + "#{process['max_respawns']} every #{process['respawn_window']} seconds"
            puts "||".color(process['log_color']) + " Restart mode        " + process['restart_mode']
            puts "||".color(process['log_color']) + " Log path            " + (process['log_path'] || "none specified")
            instances = stats['instances'][process['name']]
            if instances.empty?
              puts "||".color(process['log_color']) + " No processes running."
            else
              instances.each do |instance|
                print "|| => ".color(process['log_color']) + instance['description'].to_s.ljust(17, ' ').color(process['log_color'])
                if instance['running']
                  print 'Running'.color("32")
                else
                  print 'Stopped'.color("31")
                end
                print "   " + formatted_timestamp(instance['started_at']).ljust(10, ' ')
                print "   pid: " + instance['pid'].to_s.ljust(7, ' ')
                print "   respawns: " + instance['respawns'].to_s.ljust(7, ' ')
                puts
              end
            end
          end
        end
      else
        puts "#{@config.app_name} supervisor not running"
      end
    end

    def kill
      Dir[File.join(@config.pid_root, '*.pid')].each do |pid_path|
        name = pid_path.split('/').last.gsub(/\.pid\z/, '')
        pid = File.read(pid_path).to_i
        begin
          ::Process.kill('KILL', pid)
          puts "Sent KILL to #{pid} (#{name})"
        rescue Errno::ESRCH
        end
        FileUtils.rm(pid_path)
      end
    end

    private

    def send_to_socket(command, options = {})

      socket = UNIXSocket.new(@config.sock_path)
      # Get the connection confirmation
      connection = socket.gets
      return false unless connection == 'READY'
      # Send a command.
    ensure
      socket.close rescue nil
    end

    def running?
      if pid = current_pid
        ::Process.getpgid(pid) ? true : false
      else
        false
      end
    rescue Errno::ESRCH
      false
    end

    def current_pid
      if File.exist?(pid_path)
        pid_file = File.read(pid_path).strip
        pid_file.length > 0 ? pid_file.to_i : nil
      else
        nil
      end
    end

    def pid_path
      File.join(@config.pid_root, 'procodile.pid')
    end

    def process_names_from_cli_option
      if @cli_options[:processes]
        processes = @cli_options[:processes].split(',')
        if processes.empty?
          raise Error, "No process names provided"
        end
        processes.each do |process|
          process_name, _ = process.split('.', 2)
          unless @config.process_list.keys.include?(process_name.to_s)
            raise Error, "Process '#{process_name}' is not configured. You may need to reload your config."
          end
        end
        processes
      else
        nil
      end
    end

    def formatted_timestamp(timestamp)
      return '' if timestamp.nil?
      timestamp = Time.at(timestamp)
      if timestamp > (Time.now - (60 * 60 * 24))
        timestamp.strftime("%H:%M")
      else
        timestamp.strftime("%d/%m/%Y")
      end
    end

  end
end
