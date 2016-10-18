require 'procodile/logger'

module Procodile
  class Instance

    attr_accessor :pid
    attr_reader :id
    attr_accessor :process
    attr_accessor :respawnable

    def initialize(process, id)
      @process = process
      @id = id
      @respawns = 0
      @respawnable = true
      @started_at = nil
    end

    #
    # Return a description for this instance
    #
    def description
      "#{@process.name}.#{@id}"
    end

    #
    # Return the status of this instance
    #
    def status
      if stopped?
        'Stopped'
      elsif stopping?
        'Stopping'
      elsif running?
        'Running'
      else
        'Unknown'
      end
    end

    #
    # Return an array of environment variables that should be set
    #
    def environment_variables
      @process.config.environment_variables.merge({
        'PID_FILE' => self.pid_file_path,
        'APP_ROOT' => @process.config.root
      })
    end

    #
    # Should this instance still be monitored by the supervisor?
    #
    def unmonitored?
      @monitored == false
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
    def start(options = {}, &block)
      if stopping?
        Procodile.log(@process.log_color, description, "Process is stopped/stopping therefore cannot be started again.")
        return false
      end

      update_pid
      if running?
        # If the PID in the file is already running, we should just just continue
        # to monitor this process rather than spawning a new one.
        Procodile.log(@process.log_color, description, "Already running with PID #{@pid}")
        nil
      else
        if self.process.log_path
          log_destination = File.open(self.process.log_path, 'a')
          return_value = nil
        else
          reader, writer = IO.pipe
          log_destination = writer
          return_value = reader
        end

        Dir.chdir(@process.config.root)
        @pid = ::Process.spawn(environment_variables, @process.command, :out => log_destination, :err => log_destination, :pgroup => true)
        Procodile.log(@process.log_color, description, "Started with PID #{@pid}")
        File.open(pid_file_path, 'w') { |f| f.write(@pid.to_s + "\n") }
        ::Process.detach(@pid)
        @started_at = Time.now

        if block_given?
          block.call(self, return_value)
        end

        return_value
      end
    end

    #
    # Is this instance supposed to be stopping/be stopped?
    #
    def stopping?
      @stopping ? true : false
    end

    #
    # Is this stopped?
    #
    def stopped?
      @stopped || false
    end

    #
    # Send this signal the signal to stop and mark the instance in a state that
    # tells us that we want it to be stopped.
    #
    def stop
      @stopping = Time.now
      update_pid
      if self.running?
        Procodile.log(@process.log_color, description, "Sending #{@process.term_signal} to #{@pid}")
        ::Process.kill(@process.term_signal, pid)
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
      unmonitor
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
    def restart(&block)
      Procodile.log(@process.log_color, description, "Restarting using #{@process.restart_mode} mode")
      update_pid
      case @process.restart_mode
      when 'usr1', 'usr2'
        if running?
          ::Process.kill(@process.restart_mode.upcase, @pid)
          Procodile.log(@process.log_color, description, "Sent #{@process.restart_mode.upcase} signal to process #{@pid}")
        else
          Procodile.log(@process.log_color, description, "Process not running already. Starting it.")
          on_stop
          block.call(@process.create_instance)
        end
        nil
      when 'start-term'
        # Create a new instance and start it
        new_instance = @process.create_instance
        block.call(new_instance)
        # Send a term to the old one
        stop
        # Return the instance
        new_instance
      when 'term-start'
        # Stop our process
        stop
        new_instance = @process.create_instance
        Thread.new do
          # Wait for this process to stop
          sleep 0.5 while running?
          # When it's no running, create the new one
          block.call(new_instance)
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
      # Don't do any checking if we're in the midst of a restart
      return if unmonitored?

      if self.running?
        # Everything is OK. The process is running.
        true
      else
        # If the process isn't running any more, update the PID in our memory from
        # the file in case the process has changed itself.
        return check if update_pid

        if @respawnable
          if can_respawn?
            Procodile.log(@process.log_color, description, "Process has stopped. Respawning...")
            options[:on_start] ? start(&options[:on_start]) : start
            add_respawn
          elsif respawns >= @process.max_respawns
            Procodile.log(@process.log_color, description, "\e[41;37mWarning:\e[0m\e[31m this process has been respawned #{respawns} times and keeps dying.\e[0m")
            Procodile.log(@process.log_color, description, "It will not be respawned automatically any longer and will no longer be managed.".color(31))
            tidy
            unmonitor
          end
        else
          Procodile.log(@process.log_color, description, "Process has stopped. Respawning not available.")
          tidy
          unmonitor
        end
      end
    end

    #
    # Mark this process as dead and tidy up after it
    #
    def unmonitor
      @monitored = false
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
        :started_at => @started_at ? @started_at.to_i : nil
      }
    end

  end
end
