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
        raise Error, "#{@config.app_name} already running (PID: #{current_pid})"
      end
      if @cli_options[:foreground]
        File.open(pid_path, 'w') { |f| f.write(::Process.pid) }
        Supervisor.new(@config).start
      else
        FileUtils.rm_f(File.join(@config.pid_root, "*.pid"))
        pid = fork do
          STDOUT.reopen(log_path, 'a')
          STDOUT.sync = true
          STDERR.reopen(log_path, 'a')
          STDERR.sync = true
          Supervisor.new(@config).start
        end
        ::Process.detach(pid)
        File.open(pid_path, 'w') { |f| f.write(pid) }
        puts "Started #{@config.app_name} supervisor with PID #{pid}"
      end
    end

    def stop
      if running?
        options = {}
        if @cli_options[:processes]
          processes = @cli_options[:processes].split(',')
          instances = ControlClient.run(@config.sock_path, 'stop', :processes => processes)
        else
          instances = ControlClient.run(@config.sock_path, 'stop')
        end
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
        if @cli_options[:processes]
          processes = @cli_options[:processes].split(',')
          instances = ControlClient.run(@config.sock_path, 'restart', :processes => processes)
        else
          instances = ControlClient.run(@config.sock_path, 'restart')
        end

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
        puts "This will stop the supervisor only. Any processes that it started will no longer be managed."
        puts "They will need to be stopped manually. \e[34mDo you wish to continue? (yes/NO)\e[0m"
        if ['y', 'yes'].include?($stdin.gets.to_s.strip.downcase)
          ::Process.kill('TERM', current_pid)
          puts "We've asked it to stop. It'll probably be done in a moment."
        else
          puts "OK. That's fine. You can just run `stop` to stop processes too."
        end
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
        #puts "#{@config.app_name} running (PID: #{current_pid})"
        #::Process.kill('USR2', current_pid)
        #puts "Instance status details added to #{log_path}"
        puts ControlClient.run(@config.sock_path, 'status')
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
      File.join(@config.pid_root, 'supervisor.pid')
    end

    def log_path
      File.join(@config.log_root, 'supervisor.log')
    end

  end
end
