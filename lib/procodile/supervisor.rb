require 'procodile/control_server'

module Procodile
  class Supervisor

    attr_reader :config
    attr_reader :processes

    def initialize(config)
      @config = config
      @processes = {}
      @readers = {}
      @signal_handler = SignalHandler.new('TERM', 'USR1', 'USR2', 'INT', 'HUP')
      @signal_handler.register('TERM') { stop_supervisor }
      @signal_handler.register('INT') { stop }
      @signal_handler.register('USR1') { restart }
      @signal_handler.register('USR2') { status }
      @signal_handler.register('HUP') { reload_config }
    end

    def start(options = {})
      Procodile.log nil, "system", "#{@config.app_name} supervisor started with PID #{::Process.pid}"
      Thread.new do
        socket = ControlServer.new(self)
        socket.listen
      end
      start_processes(options[:processes])
      watch_for_output
      supervise
    end

    def start_processes(types = [])
      Array.new.tap do |instances_started|
        @config.processes.each do |name, process|
          next if types && !types.include?(name.to_s) # Not a process we want
          next if @processes.keys.include?(process)   # Process type already running
          instances = start_instances(process.generate_instances)
          instances_started.push(*instances)
        end
      end
    end

    def stop(options = {})
      Array.new.tap do |instances_stopped|
        if options[:processes].nil?
          return if @stopping
          @stopping = true
          Procodile.log nil, "system", "Stopping all #{@config.app_name} processes"
            @processes.each do |_, instances|
              instances.each do |instance|
                instance.stop
                instances_stopped << instance
              end
            end
        else
          instances = process_names_to_instances(options[:processes])
          Procodile.log nil, "system", "Stopping #{instances.size} process(es)"
          instances.each do |instance|
            instance.stop
            instances_stopped << instance
          end
        end
      end
    end

    def restart(options = {})
      @config.reload
      Array.new.tap do |instances_restarted|
        if options[:processes].nil?
          Procodile.log nil, "system", "Restarting all #{@config.app_name} processes"
          @processes.each do |_, instances|
            instances.each do |instance|
              instance.restart
              instances_restarted << instance
            end
          end
        else
          instances = process_names_to_instances(options[:processes])
          Procodile.log nil, "system", "Restarting #{instances.size} process(es)"
          instances.each do |instance|
            instance.restart
            instances_restarted << instance
          end
        end
      end
    end

    def stop_supervisor
      Procodile.log nil, 'system', "Stopping #{@config.app_name} supervisor"
      FileUtils.rm_f(File.join(@config.pid_root, 'supervisor.pid'))
      ::Process.exit 0
    end

    def supervise
      loop do
        # Tidy up any instances that we no longer wish to be managed. They will
        # be removed from the list.
        remove_dead_instances

        # Remove processes that have been stopped
        remove_stopped_instances

        # Check all instances that we manage and let them do their things.
        @processes.each do |_, instances|
          instances.each(&:check)
        end

        # If the processes go away, we can stop the supervisor now
        if @processes.size == 0
          Procodile.log nil, "system", "All processes have stopped"
          stop_supervisor
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

    def watch_for_output
      Thread.new do
        loop do
          io = IO.select([@signal_handler.pipe[:reader]] + @readers.keys, nil, nil, 30)
          @signal_handler.handle
          if io
            io.first.each do |reader|
              next if reader == @signal_handler.pipe[:reader]
              if reader.eof?
                @readers.delete(reader)
              else
                data = reader.gets
                if instance = @readers[reader]
                  Procodile.log instance.process.log_color, instance.description, "=> ".color(instance.process.log_color) + data
                else
                  Procodile.log nil, 'unknown', data
                end
              end
            end
          end
        end
      end
    end

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
        io = instance.start
        @readers[io] = instance if io
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

    def process_names_to_instances(names)
      names.each_with_object([]) do |name, array|
        if name =~ /\A(.*)\.(\d+)\z/
          process_name, id = $1, $2
          @processes.each do |process, instances|
            next unless process.name == process_name
            instances.each do |instance|
              next unless instance.id == id.to_i
              array << instance
            end
          end
        else
          @processes.each do |process, instances|
            next unless process.name == name
            instances.each { |i| array << i}
          end
        end
      end
    end

  end
end
