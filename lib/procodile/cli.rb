require 'fileutils'
require 'procodile/version'
require 'procodile/error'
require 'procodile/message'
require 'procodile/supervisor'
require 'procodile/signal_handler'
require 'procodile/control_client'

module Procodile
  class CLI

    def self.commands
      @commands ||= {}
    end

    def self.desc(description)
      @description = description
    end

    def self.options(&block)
      @options = block
    end

    def self.command(name)
      commands[name] = {:name => name, :description => @description, :options => @options}
      @description = nil
      @options = nil
    end

    attr_accessor :options
    attr_accessor :config

    def initialize
      @options = {}
    end

    def dispatch(command)
      if self.class.commands.keys.include?(command.to_sym)
        public_send(command)
      else
        raise Error, "Invalid command '#{command}'"
      end
    end

    #
    # Help
    #

    desc "Shows this help output"
    command def help
      puts "\e[45;37mWelcome to Procodile v#{Procodile::VERSION}\e[0m"
      puts "For documentation see https://adam.ac/procodile."
      puts

      puts "The following commands are supported:"
      puts
      self.class.commands.each do |method, options|
        puts "  \e[34m#{method.to_s.ljust(18, ' ')}\e[0m #{options[:description]}"
      end
      puts
      puts "For details for the options available for each command, use the --help option."
      puts "For example 'procodile start --help'."
    end

    #
    # Start
    #

    desc "Starts processes and/or the supervisor"
    options do |opts, cli|
      opts.on("-p", "--processes a,b,c", "Only start the listed processes or process types") do |processes|
        cli.options[:processes] = processes
      end

      opts.on("-t", "--tag TAGNAME", "Tag all started processes with the given tag") do |tag|
        cli.options[:tag] = tag
      end

      opts.on("--no-supervisor", "Do not start a supervisor if its not running") do
        cli.options[:start_supervisor] = false
      end

      opts.on("--no-processes", "Do not start any processes (only applicable when supervisor is stopped)") do
        cli.options[:start_processes] = false
      end

      opts.on("-f", "--foreground", "Run the supervisor in the foreground") do
        cli.options[:foreground] = true
      end

      opts.on("--clean", "Remove all previous pid and sock files before starting") do
        cli.options[:clean] = true
      end

      opts.on("--no-respawn", "Disable respawning for all processes") do
        cli.options[:respawn] = false
      end

      opts.on("--stop-when-none", "Stop the supervisor when all processes are stopped") do
        cli.options[:stop_when_none] = true
      end

      opts.on("-x", "--proxy", "Enables the Procodile proxy service") do
        cli.options[:proxy] = true
      end

      opts.on("-d", "--dev", "Run in development mode") do
        cli.options[:development] = true
        cli.options[:respawn] = false
        cli.options[:foreground] = true
        cli.options[:stop_when_none] = true
        cli.options[:proxy] = true
      end
    end
    command def start
      if supervisor_running?
        if @options[:foreground]
          raise Error, "Cannot be started in the foreground because supervisor already running"
        end

        if @options.has_key?(:respawn)
          raise Error, "Cannot disable respawning because supervisor is already running"
        end

        if @options[:stop_when_none]
          raise Error, "Cannot stop supervisor when none running because supervisor is already running"
        end

        if @options[:proxy]
          raise Error, "Cannot enable the proxy when the supervisor is running"
        end

        instances = ControlClient.run(@config.sock_path, 'start_processes', :processes => process_names_from_cli_option, :tag => @options[:tag])
        if instances.empty?
          puts "No processes to start."
        else
          instances.each do |instance|
            puts "Started".color(32) + " #{instance['description']} (PID: #{instance['pid']})"
          end
        end
        return
      else
        # The supervisor isn't actually running. We need to start it before processes can be
        # begin being processed
        if @options[:start_supervisor] == false
          raise Error, "Supervisor is not running and cannot be started because --no-supervisor is set"
        else
          self.class.start_supervisor(@config, @options) do |supervisor|
            unless @options[:start_processes] == false
              supervisor.start_processes(process_names_from_cli_option, :tag => @options[:tag])
            end
          end
        end
      end
    end

    #
    # Stop
    #

    desc "Stops processes and/or the supervisor"
    options do |opts, cli|
      opts.on("-p", "--processes a,b,c", "Only stop the listed processes or process types") do |processes|
        cli.options[:processes] = processes
      end

      opts.on("-s", "--stop-supervisor", "Stop the supervisor process when all processes are stopped") do
        cli.options[:stop_supervisor] = true
      end

      opts.on("--wait", "Wait until supervisor has stopped before exiting") do
        cli.options[:wait_until_supervisor_stopped] = true
      end

    end
    command def stop
      if supervisor_running?
        options = {}
        instances = ControlClient.run(@config.sock_path, 'stop', :processes => process_names_from_cli_option, :stop_supervisor => @options[:stop_supervisor])
        if instances.empty?
          puts "No processes were stopped."
        else
          instances.each do |instance|
            puts "Stopped".color(31) + " #{instance['description']} (PID: #{instance['pid']})"
          end
        end

        if @options[:stop_supervisor]
          puts "Supervisor will be stopped when processes are stopped."
        end

        if @options[:wait_until_supervisor_stopped]
          puts "Waiting for supervisor to stop..."
          loop do
            sleep 1
            if supervisor_running?
              sleep 1
            else
              puts "Supervisor has stopped"
              exit 0
            end
          end
        end
      else
        raise Error, "Procodile supervisor isn't running"
      end
    end

    #
    # Restart
    #

    desc "Restart processes"
    options do |opts, cli|
      opts.on("-p", "--processes a,b,c", "Only restart the listed processes or process types") do |processes|
        cli.options[:processes] = processes
      end

      opts.on("-t", "--tag TAGNAME", "Tag all started processes with the given tag") do |tag|
        cli.options[:tag] = tag
      end
    end
    command def restart
      if supervisor_running?
        instances = ControlClient.run(@config.sock_path, 'restart', :processes => process_names_from_cli_option, :tag => @options[:tag])
        if instances.empty?
          puts "There are no processes to restart."
        else
          instances.each do |old_instance, new_instance|
            if old_instance && new_instance
              if old_instance['description'] == new_instance['description']
                puts "Restarted".color(35) + " #{old_instance['description']}"
              else
                puts "Restarted".color(35) + " #{old_instance['description']} -> #{new_instance['description']}"
              end
            elsif old_instance
              puts "Stopped".color(31) + " #{old_instance['description']}"
            elsif new_instance
              puts "Started".color(32) + " #{new_instance['description']}"
            end
            $stdout.flush
          end
        end
      else
        raise Error, "Procodile supervisor isn't running"
      end
    end

    #
    # Reload Config
    #

    desc "Reload Procodile configuration"
    command def reload
      if supervisor_running?
        ControlClient.run(@config.sock_path, 'reload_config')
        puts "Reloaded Procodile config"
      else
        raise Error, "Procodile supervisor isn't running"
      end
    end

    #
    # Check process concurrency
    #

    desc "Check process concurrency"
    options do |opts, cli|
      opts.on("--no-reload", "Do not reload the configuration before checking") do |processes|
        cli.options[:reload] = false
      end
    end
    command def check_concurrency
      if supervisor_running?
        reply = ControlClient.run(@config.sock_path, 'check_concurrency', :reload => @options[:reload])
        if reply['started'].empty? && reply['stopped'].empty?
          puts "Processes are running as configured"
        else
          reply['started'].each do |instance|
            puts "Started".color(32) + " #{instance['description']} (PID: #{instance['pid']})"
          end

          reply['stopped'].each do |instance|
            puts "Stopped".color(31) + " #{instance['description']} (PID: #{instance['pid']})"
          end
        end
      else
        raise Error, "Procodile supervisor isn't running"
      end
    end

    #
    # Status
    #

    desc "Show the current status of processes"
    options do |opts, cli|
      opts.on("--json", "Return the status as a JSON hash") do
        cli.options[:json] = true
      end

      opts.on("--simple", "Return overall status") do
        cli.options[:simple] = true
      end
    end
    command def status
      if supervisor_running?
        status = ControlClient.run(@config.sock_path, 'status')
        if @options[:json]
          puts status.to_json
        elsif @options[:simple]
          if status['messages'].empty?
            message = status['instances'].map { |p,i| "#{p}[#{i.size}]" }
            puts "OK || #{message.join(', ')}"
          else
            message = status['messages'].map { |p| Message.parse(p) }.join(', ')
            puts "Issues || #{message}"
          end
        else
          require 'procodile/status_cli_output'
          StatusCLIOutput.new(status).print_all
        end
      else
        if @options[:simple]
          puts "NotRunning || Procodile supervisor isn't running"
        else
          raise Error, "Procodile supervisor isn't running"
        end
      end
    end

    #
    # Kill
    #
    desc "Forcefully kill all known processes"
    command def kill
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

    #
    # Run a command with a procodile environment
    #
    desc "Run a command within the environment"
    command def run
      desired_command = ARGV.drop(1).join(' ')
      exec(@config.environment_variables, desired_command)
    end

    #
    # Run the configured console command
    #
    desc "Open a console within the environment"
    command def console
      if cmd = @config.console_command
        environment = @config.environment_variables
        exec(environment, cmd)
      else
        raise Error, "No console command has been configured in the Procfile"
      end
    end

    #
    # Open up the procodile log if it exists
    #
    desc "Open a console within the environment"
    options do |opts, cli|
      opts.on("-f", "Wait for additional data and display it straight away") do
        cli.options[:wait] = true
      end

      opts.on("-n LINES", "The number of previous lines to return") do |lines|
        cli.options[:lines] = lines.to_i
      end
    end
    command def log
      if File.exist?(@config.log_path)
        opts = []
        opts << "-f" if options[:wait]
        opts << "-n #{options[:lines]}" if options[:lines]
        exec("tail #{opts.join(' ')} #{@config.log_path}")
      else
        raise Error, "No log file exists at #{@config.log_path}"
      end
    end


    private

    def supervisor_running?
      if pid = current_pid
        ::Process.getpgid(pid) ? true : false
      else
        false
      end
    rescue Errno::ESRCH
      false
    end

    def current_pid
      if File.exist?(@config.supervisor_pid_path)
        pid_file = File.read(@config.supervisor_pid_path).strip
        pid_file.length > 0 ? pid_file.to_i : nil
      else
        nil
      end
    end

    def process_names_from_cli_option
      if @options[:processes]
        processes = @options[:processes].split(',')
        if processes.empty?
          raise Error, "No process names provided"
        end
        #processes.each do |process|
        #  process_name, _ = process.split('.', 2)
        #  unless @config.process_list.keys.include?(process_name.to_s)
        #    raise Error, "Process '#{process_name}' is not configured. You may need to reload your config."
        #  end
        #end
        processes
      else
        nil
      end
    end

    def self.start_supervisor(config, options = {}, &after_start)
      run_options = {}
      run_options[:respawn] = options[:respawn]
      run_options[:stop_when_none] = options[:stop_when_none]
      run_options[:proxy] = options[:proxy]
      run_options[:force_single_log] = options[:foreground]

      if options[:clean]
        FileUtils.rm_rf(Dir[File.join(config.pid_root, '*')])
        puts "Emptied PID directory"
      end

      if !Dir[File.join(config.pid_root, "*")].empty?
        raise Error, "The PID directory (#{config.pid_root}) is not empty. Cannot start unless things are clean."
      end

      $0="[procodile] #{config.app_name} (#{config.root})"
      if options[:foreground]
        File.open(config.supervisor_pid_path, 'w') { |f| f.write(::Process.pid) }
        Supervisor.new(config, run_options).start(&after_start)
      else
        FileUtils.rm_f(File.join(config.pid_root, "*.pid"))
        pid = fork do
          STDOUT.reopen(config.log_path, 'a')
          STDOUT.sync = true
          STDERR.reopen(config.log_path, 'a')
          STDERR.sync = true
          Supervisor.new(config, run_options).start(&after_start)
        end
        ::Process.detach(pid)
        File.open(config.supervisor_pid_path, 'w') { |f| f.write(pid) }
        puts "Started Procodile supervisor with PID #{pid}"
      end
    end

  end
end
