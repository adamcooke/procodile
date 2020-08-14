require 'procodile/logger'
require 'procodile/rbenv'

module Procodile
  class Instance

    attr_accessor :pid
    attr_reader :id
    attr_accessor :process
    attr_reader :tag
    attr_accessor :port

    def initialize(supervisor, process, id)
      @supervisor = supervisor
      @process = process
      @id = id
      @respawns = 0
      @started_at = nil
    end

    #
    # Return a description for this instance
    #
    def description
      "#{@process.name}.#{@id}"
    end

    #
    # Return the status of this instance
    #
    def status
      if stopped?
        'Stopped'
      elsif stopping?
        'Stopping'
      elsif running?
        'Running'
      elsif failed?
        'Failed'
      else
        'Unknown'
      end
    end

    #
    # Should this process be running?
    #
    def should_be_running?
      if stopped? || stopping?
        false
      else
        true
      end
    end

    #
    # Return an array of environment variables that should be set
    #
    def environment_variables
      vars = @process.environment_variables.merge({
        'PROC_NAME' => self.description,
        'PID_FILE' => self.pid_file_path,
        'APP_ROOT' => @process.config.root
      })
      vars['PORT'] = @port.to_s if @port
      vars
    end

    #
    # Return the path to this instance's PID file
    #
    def pid_file_path
      File.join(@process.config.pid_root, "#{description}.pid")
    end

    #
    # Return the PID that is in the instances process PID file
    #
    def pid_from_file
      if File.exist?(pid_file_path)
        pid = File.read(pid_file_path)
        pid.length > 0 ? pid.strip.to_i : nil
      else
        nil
      end
    end

    #
    # Is this process running? Pass an option to check the given PID instead of the instance
    #
    def running?
      if @pid
        ::Process.getpgid(@pid) ? true : false
      else
        false
      end
    rescue Errno::ESRCH
      false
    end

    #
    # Start a new instance of this process
    #
    def start
      if stopping?
        Procodile.log(@process.log_color, description, "Process is stopped/stopping therefore cannot be started again.")
        return false
      end

      update_pid
      if running?
        Procodile.log(@process.log_color, description, "Already running with PID #{@pid}")
        nil
      else
        if @supervisor.run_options[:port_allocations] && chosen_port = @supervisor.run_options[:port_allocations][@process.name]
          if chosen_port == 0
            allocate_port
          else
            @port = chosen_port
            Procodile.log(@process.log_color, description, "Assigned #{chosen_port} to process")
          end
        elsif @process.proxy? && @supervisor.tcp_proxy
          # Allocate a port randomly if a proxy is needed
          allocate_port
        elsif @process.allocate_port_from && @process.restart_mode != 'start-term'
          # Allocate ports to this process sequentially from the starting port
          allocated_ports = (@supervisor.processes[@process] ? @supervisor.processes[@process].select(&:running?) : []).map(&:port)
          proposed_port = @process.allocate_port_from
          until @port
            unless allocated_ports.include?(proposed_port)
              @port = proposed_port
            end
            proposed_port += 1
          end
        end

        if self.process.log_path && @supervisor.run_options[:force_single_log] != true
          log_destination = File.open(self.process.log_path, 'a')
          io = nil
        else
          reader, writer = IO.pipe
          log_destination = writer
          io = reader
        end
        @tag = @supervisor.tag.dup if @supervisor.tag
        Dir.chdir(@process.config.root)
        Rbenv.without do
          @pid = ::Process.spawn(environment_variables, @process.command, :out => log_destination, :err => log_destination, :pgroup => true)
        end
        log_destination.close
        File.open(pid_file_path, 'w') { |f| f.write(@pid.to_s + "\n") }
        @supervisor.add_instance(self, io)
        ::Process.detach(@pid)
        Procodile.log(@process.log_color, description, "Started with PID #{@pid}" + (@tag ? " (tagged with #{@tag})" : ''))
        if self.process.log_path && io.nil?
          Procodile.log(@process.log_color, description, "Logging to #{self.process.log_path}")
        end
        @started_at = Time.now
      end
    end

    #
    # Is this instance supposed to be stopping/be stopped?
    #
    def stopping?
      @stopping ? true : false
    end

    #
    # Is this stopped?
    #
    def stopped?
      @stopped || false
    end

    #
    # Has this failed?
    #
    def failed?
      @failed ? true : false
    end

    #
    # Send this signal the signal to stop and mark the instance in a state that
    # tells us that we want it to be stopped.
    #
    def stop
      @stopping = Time.now
      update_pid
      if self.running?
        Array(@process.term_signal).each do |signal|
          Procodile.log(@process.log_color, description, "Sending #{signal} to #{@pid}")
          ::Process.kill(signal, pid)
        end
      else
        Procodile.log(@process.log_color, description, "Process already stopped")
      end
    end

    #
    # A method that will be called when this instance has been stopped and it isn't going to be
    # started again
    #
    def on_stop
      @started_at = nil
      @stopped = true
      tidy
    end

    #
    # Tidy up when this process isn't needed any more
    #
    def tidy
      FileUtils.rm_f(self.pid_file_path)
      Procodile.log(@process.log_color, description, "Removed PID file")
    end

    #
    # Retarts the process using the appropriate method from the process configuraiton
    #
    def restart
      Procodile.log(@process.log_color, description, "Restarting using #{@process.restart_mode} mode")
      update_pid
      case @process.restart_mode
      when 'usr1', 'usr2'
        if running?
          ::Process.kill(@process.restart_mode.upcase, @pid)
          @tag = @supervisor.tag if @supervisor.tag
          Procodile.log(@process.log_color, description, "Sent #{@process.restart_mode.upcase} signal to process #{@pid}")
        else
          Procodile.log(@process.log_color, description, "Process not running already. Starting it.")
          on_stop
          new_instance = @process.create_instance(@supervisor)
          new_instance.port = self.port
          new_instance.start
        end
        self
      when 'start-term'
        new_instance = @process.create_instance(@supervisor)
        new_instance.start
        stop
        new_instance
      when 'term-start'
        stop
        new_instance = @process.create_instance(@supervisor)
        new_instance.port = self.port
        Thread.new do
          sleep 0.5 while running?
          new_instance.start
        end
        new_instance
      end
    end

    #
    # Update the locally cached PID from that stored on the file system.
    #
    def update_pid
      pid_from_file = self.pid_from_file
      if pid_from_file && pid_from_file != @pid
        @pid = pid_from_file
        @started_at = File.mtime(self.pid_file_path)
        Procodile.log(@process.log_color, description, "PID file changed. Updated pid to #{@pid}")
        true
      else
        false
      end
    end

    #
    # Check the status of this process and handle as appropriate.
    #
    def check(options = {})
      return if failed?

      if self.running?
        # Everything is OK. The process is running.
        true
      else
        # If the process isn't running any more, update the PID in our memory from
        # the file in case the process has changed itself.
        return check if update_pid

        if @supervisor.allow_respawning?
          if can_respawn?
            Procodile.log(@process.log_color, description, "Process has stopped. Respawning...")
            start
            add_respawn
          elsif respawns >= @process.max_respawns
            Procodile.log(@process.log_color, description, "\e[41;37mWarning:\e[0m\e[31m this process has been respawned #{respawns} times and keeps dying.\e[0m")
            Procodile.log(@process.log_color, description, "It will not be respawned automatically any longer and will no longer be managed.".color(31))
            @failed = Time.now
            tidy
          end
        else
          Procodile.log(@process.log_color, description, "Process has stopped. Respawning not available.")
          @failed = Time.now
          tidy
        end
      end
    end

    #
    # Can this process be respawned if needed?
    #
    def can_respawn?
      !stopping? && (respawns + 1) <= @process.max_respawns
    end

    #
    # Return the number of times this process has been respawned in the last hour
    #
    def respawns
      if @respawns.nil? || @last_respawn.nil? || @last_respawn < (Time.now - @process.respawn_window)
        0
      else
        @respawns
      end
    end

    #
    # Increment the counter of respawns for this process
    #
    def add_respawn
      if @last_respawn && @last_respawn < (Time.now - @process.respawn_window)
        @respawns = 1
      else
        @last_respawn = Time.now
        @respawns += 1
      end
    end

    #
    # Return this instance as a hash
    #
    def to_hash
      {
        :description => self.description,
        :pid => self.pid,
        :respawns => self.respawns,
        :status => self.status,
        :running => self.running?,
        :started_at => @started_at ? @started_at.to_i : nil,
        :tag => self.tag,
        :port => @port
      }
    end


    #
    # Find a port number for this instance to listen on. We just check that nothing is already listening on it.
    # The process is expected to take it straight away if it wants it.
    #
    def allocate_port(max_attempts = 10)
      attempts = 0
      until @port
        attempts += 1
        possible_port = rand(10000) + 20000
        if self.port_available?(possible_port)
          Procodile.log(@process.log_color, description, "Allocated port as #{possible_port}")
          return @port = possible_port
        elsif attempts >= max_attempts
          raise Procodile::Error, "Couldn't allocate port for #{instance.name}"
        end
      end
    end

    #
    # Is the given port available?
    #
    def port_available?(port)
      case @process.network_protocol
      when 'tcp'
        server = TCPServer.new('127.0.0.1', port)
        server.close
        true
      when 'udp'
        server = UDPSocket.new
        server.bind('127.0.0.1', port)
        server.close
        true
      else
        raise Procodile::Error, "Invalid network_protocol '#{@process.network_protocol}'"
      end
    rescue Errno::EADDRINUSE => e
      false
    end

  end
end
