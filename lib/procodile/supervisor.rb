module Procodile
  class Supervisor

    # Create a new supervisor instance that will be monitoring the
    # processes that have been provided.
    def initialize(config)
      @config = config
      @instances = []

      signal_handler = SignalHandler.new('TERM', 'USR1', 'USR2', 'INT', 'HUP')
      signal_handler.register('INT') { stop }
      signal_handler.register('USR1') { restart }
      signal_handler.register('USR2') { status }
      signal_handler.register('TERM') { stop_supervisor }
    end

    def start
      Procodile.log nil, "system", "#{@config.app_name} supervisor started with PID #{::Process.pid}"
      @config.processes.each do |name, process|
        process.generate_instances.each do |instance|
          instance.start
          @instances << instance
        end
      end
      supervise
    end

    def stop
      return if @stopping
      @stopping = true
      Procodile.log nil, "system", "Stopping all #{@config.app_name} processes"
      @instances.each(&:stop)
    end

    def stop_supervisor
      Procodile.log nil, 'system', "Stopping #{@config.app_name} supervisor"
      FileUtils.rm_f(File.join(@config.pid_root, 'supervisor.pid'))
      ::Process.exit 0
    end

    def restart
      Procodile.log nil, 'system', "Restarting all #{@config.app_name} processes"
      @instances.each(&:restart)
    end

    def status
      Procodile.log '37;44', 'status', "Status as at: #{Time.now.utc.to_s}"
      @instances.each do |instance|
        if instance.running?
          Procodile.log '37;44', 'status', "#{instance.description} is RUNNING (pid #{instance.pid}). Respawned #{instance.respawns} time(s)"
        else
          Procodile.log '37;44', 'status', "#{instance.description} is STOPPED"
        end
      end
    end

    def supervise
      loop do
        # Tidy up any instances that we no longer wish to be managed. They will
        # be removed from the list.
        remove_dead_instances

        if @stopping
          # If the system is stopping, we'll remove any instances that have already
          # stopped and trigger their on_stop callback.
          remove_stopped_instances

          # When all the instances we manage have gone away, we can stop ourself.
          if @instances.size > 0
            Procodile.log nil, "system", "Waiting for #{@instances.size} processes to stop"
          else
            Procodile.log nil, "system", "All processes have stopped"
            stop_supervisor
          end
        else
          # Check all instances that we manage and let them do their things.
          @instances.each(&:check)
        end

        sleep 5
      end
    end

    private

    def remove_dead_instances
      @instances.reject!(&:dead?)
    end

    def remove_stopped_instances
      @instances.reject! do |instance|
        if instance.running?
          false
        else
          instance.on_stop
          true
        end
      end
    end

  end
end
