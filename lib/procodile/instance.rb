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
    end

    #
    # Return a description for this instance
    #
    def description
      "#{@process.name}.#{@id}"
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
    def running?(force_pid = nil)
      if force_pid || @pid
        ::Process.getpgid(force_pid || @pid) ? true : false
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
      @stopping = false
      existing_pid = self.pid_from_file
      if running?(existing_pid)
        # If the PID in the file is already running, we should just just continue
        # to monitor this process rather than spawning a new one.
        @pid = existing_pid
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
        @pid = ::Process.spawn({'PID_FILE' => pid_file_path}, @process.command, :out => log_destination, :err => log_destination, :pgroup => true)
        Procodile.log(@process.log_color, description, "Started with PID #{@pid}")
        File.open(pid_file_path, 'w') { |f| f.write(@pid.to_s + "\n") }
        ::Process.detach(@pid)

        return_value
      end
    end

    #
    # Is this instance supposed to be stopping/be stopped?
    #
    def stopping?
      @stopping || false
    end

    #
    # Send this signal the signal to stop and mark the instance in a state that
    # tells us that we want it to be stopped.
    #
    def stop
      @stopping = true
      update_pid
      if self.running?
        Procodile.log(@process.log_color, description, "Sending TERM to #{@pid}")
        ::Process.kill('TERM', pid)
      else
        Procodile.log(@process.log_color, description, "Process already stopped")
      end
    end

    #
    # A method that will be called when this instance has been stopped and it isn't going to be
    # started again
    #
    def on_stop
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
    def restart
      Procodile.log(@process.log_color, description, "Restarting using #{@process.restart_mode} mode")
      @restarting = true
      update_pid
      case @process.restart_mode
      when 'usr1', 'usr2'
        if running?
          ::Process.kill(@process.restart_mode.upcase, @pid)
          Procodile.log(@process.log_color, description, "Sent #{@process.restart_mode.upcase} signal to process #{@pid}")
        else
          Procodile.log(@process.log_color, description, "Process not running already. Starting it.")
          start
        end
      when 'start-term'
        old_process_pid = @pid
        start
        Procodile.log(@process.log_color, description, "Sent TERM signal to old PID #{old_process_pid} (forgetting now)")
        ::Process.kill('TERM', old_process_pid)
      when 'term-start'
        stop
        Thread.new do
          # Wait for this process to stop and when it has, run it.
          sleep 0.5 while running?
          start
        end
      end
    ensure
      @restarting = false
    end

    #
    # Update the locally cached PID from that stored on the file system.
    #
    def update_pid
      pid_from_file = self.pid_from_file
      if pid_from_file && pid_from_file != @pid
        @pid = pid_from_file
        Procodile.log(@process.log_color, description, "PID file changed. Updated pid to #{@pid}")
        true
      else
        false
      end
    end

    #
    # Check the status of this process and handle as appropriate.
    #
    def check
      # Don't do any checking if we're in the midst of a restart
      return if @restarting
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
            start
            add_respawn
          elsif respawns >= @process.max_respawns
            Procodile.log(@process.log_color, description, "\e[41;37mWarning:\e[0m\e[31m this process has been respawned #{respawns} times and keeps dying.\e[0m")
            Procodile.log(@process.log_color, description, "It will not be respawned automatically any longer and will no longer be managed.").color(31)
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
        :running => self.running?
      }
    end

  end
end
