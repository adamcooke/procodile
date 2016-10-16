module Procodile
  class Supervisor

    # Create a new supervisor instance that will be monitoring the
    # processes that have been provided.
    def initialize(config)
      @config = config
      @processes = {}

      signal_handler = SignalHandler.new('TERM', 'USR1', 'USR2', 'INT', 'HUP')
      signal_handler.register('INT') { stop }
      signal_handler.register('USR1') { restart }
      signal_handler.register('USR2') { status }
      signal_handler.register('TERM') { stop_supervisor }
      signal_handler.register('HUP') { reload_config }
    end

    def start
      Procodile.log nil, "system", "#{@config.app_name} supervisor started with PID #{::Process.pid}"
      @config.processes.each do |name, process|
        start_instances(process.generate_instances)
      end
      supervise
    end

    def stop
      return if @stopping
      @stopping = true
      Procodile.log nil, "system", "Stopping all #{@config.app_name} processes"
      @processes.each { |_, instances| instances.each(&:stop) }
    end

    def stop_supervisor
      Procodile.log nil, 'system', "Stopping #{@config.app_name} supervisor"
      FileUtils.rm_f(File.join(@config.pid_root, 'supervisor.pid'))
      ::Process.exit 0
    end

    def restart
      Procodile.log nil, 'system', "Restarting all #{@config.app_name} processes"
      @config.reload
      @processes.each { |_, instances| instances.each(&:restart) }
    end

    def status
      Procodile.log '37;44', 'status', "Status as at: #{Time.now.utc.to_s}"
      @processes.each do |_, instances|
        instances.each do |instance|
          if instance.running?
            Procodile.log '37;44', 'status', "#{instance.description} is RUNNING (pid #{instance.pid}). Respawned #{instance.respawns} time(s)"
          else
            Procodile.log '37;44', 'status', "#{instance.description} is STOPPED"
          end
        end
      end
    end

    def supervise
      loop do
        # Tidy up any instances that we no longer wish to be managed. They will
        # be removed from the list.
        remove_dead_instances

        # Remove processes that have been stopped
        remove_stopped_instances

        if @stopping
          if @processes.size > 0
            Procodile.log nil, "system", "Waiting for #{@processes.size} processes to stop"
          else
            Procodile.log nil, "system", "All processes have stopped"
            stop_supervisor
          end
        else
          # Check all instances that we manage and let them do their things.
          @processes.each do |_, instances|
            instances.each(&:check)
          end
        end

        sleep 5
      end
    end

    def reload_config
      Procodile.log nil, "system", "Reloading configuration"
      @config.reload
      check_instance_quantities
    end

    private

    def check_instance_quantities
      @processes.each do |process, instances|
        if instances.size > process.quantity
          quantity_to_stop = instances.size - process.quantity
          Procodile.log nil, "system", "Stopping #{quantity_to_stop} #{process.name} process(es)"
          instances.last(quantity_to_stop).each(&:stop)
        elsif instances.size < process.quantity
          quantity_needed = process.quantity - instances.size
          start_id = instances.last ? instances.last.id + 1 : 1
          Procodile.log nil, "system", "Starting #{quantity_needed} more #{process.name} process(es) (start with #{start_id})"
          start_instances(process.generate_instances(quantity_needed, start_id))
        end
      end
    end

    def start_instances(instances)
      instances.each do |instance|
        instance.start
        @processes[instance.process] ||= []
        @processes[instance.process] << instance
      end
    end

    def remove_dead_instances
      @processes.each do |_, instances|
        instances.reject!(&:unmonitored?)
      end.reject! { |_, instances| instances.empty? }
    end

    def remove_stopped_instances
      @processes.each do |_, instances|
        instances.reject! do |instance|
          if !instance.running? && instance.stopping?
            instance.on_stop
            true
          else
            false
          end
        end
      end.reject! { |_, instances| instances.empty? }
    end

  end
end
