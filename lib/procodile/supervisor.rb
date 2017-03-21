require 'procodile/control_server'
require 'procodile/tcp_proxy'

module Procodile
  class Supervisor

    attr_reader :config
    attr_reader :processes
    attr_reader :started_at
    attr_reader :tag
    attr_reader :tcp_proxy
    attr_reader :run_options

    def initialize(config, run_options = {})
      @config = config
      @run_options = run_options
      @processes = {}
      @readers = {}
      @signal_handler = SignalHandler.new('TERM', 'USR1', 'USR2', 'INT', 'HUP')
      @signal_handler.register('TERM') { stop_supervisor }
      @signal_handler.register('INT') { stop(:stop_supervisor => true) }
      @signal_handler.register('USR1') { restart }
      @signal_handler.register('USR2') { }
      @signal_handler.register('HUP') { reload_config }
    end

    def allow_respawning?
      @run_options[:respawn] != false
    end

    def start(&after_start)
      Procodile.log nil, "system", "Procodile supervisor started with PID #{::Process.pid}"
      Procodile.log nil, "system", "Environment is #{@config.environment}"
      if @run_options[:respawn] == false
        Procodile.log nil, "system", "Automatic respawning is disabled"
      end
      ControlServer.start(self)
      if @run_options[:proxy]
        Procodile.log nil, "system", "Proxy is enabled"
        @tcp_proxy = TCPProxy.start(self)
      end
      watch_for_output
      @started_at = Time.now
      after_start.call(self) if block_given?
      supervise!
    rescue => e
      Procodile.log nil, "system", "Error: #{e.class} (#{e.message})"
      e.backtrace.each { |bt| Procodile.log nil, "system", "=> #{bt})" }
      stop(:stop_supervisor => true)
      supervise!
    end

    def supervise!
      loop { supervise; sleep 3 }
    end

    def start_processes(types = nil, options = {})
      @tag = options[:tag]
      reload_config
      Array.new.tap do |instances_started|
        @config.processes.each do |name, process|
          next if types && !types.include?(name.to_s)                   # Not a process we want
          next if @processes[process] && !@processes[process].empty?    # Process type already running
          instances = process.generate_instances(self).each(&:start)
          instances_started.push(*instances)
        end
      end
    end

    def stop(options = {})
      if options[:stop_supervisor]
        @run_options[:stop_when_none] = true
      end
      reload_config
      Array.new.tap do |instances_stopped|
        if options[:processes].nil?
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
      @tag = options[:tag]
      reload_config
      Array.new.tap do |instances_restarted|
        if options[:processes].nil?
          Procodile.log nil, "system", "Restarting all #{@config.app_name} processes"
          instances = @processes.values.flatten
        else
          instances = process_names_to_instances(options[:processes])
          Procodile.log nil, "system", "Restarting #{instances.size} process(es)"
        end

        # Stop any processes that are no longer wanted at this point
        instances_restarted.push(*check_instance_quantities(:stopped, options[:processes])[:stopped].map { |i| [i, nil]})

        instances.each do |instance|
          next if instance.stopping?
          new_instance = instance.restart
          instances_restarted << [instance, new_instance]
        end

        # Start any processes that are needed at this point
        instances_restarted.push(*check_instance_quantities(:started, options[:processes])[:started].map { |i| [nil, i]})
      end
    end

    def stop_supervisor
      Procodile.log nil, 'system', "Stopping Procodile supervisor"
      FileUtils.rm_f(File.join(@config.pid_root, 'procodile.pid'))
      ::Process.exit 0
    end

    def supervise
      # Tell instances that have been stopped that they have been stopped
      remove_stopped_instances

      # Remove removed processes
      remove_removed_processes

      # Check all instances that we manage and let them do their things.
      @processes.each do |_, instances|
        instances.each do |instance|
          instance.check
        end
      end

      if @run_options[:stop_when_none]
        # If the processes go away, we can stop the supervisor now
        if @processes.all? { |_,instances| instances.reject(&:failed?).size == 0 }
          Procodile.log nil, "system", "All processes have stopped"
          stop_supervisor
        end
      end
    end

    def reload_config
      Procodile.log nil, "system", "Reloading configuration"
      @config.reload
    end

    def check_concurrency(options = {})
      Procodile.log nil, "system", "Checking process concurrency"
      reload_config unless options[:reload] == false
      result = check_instance_quantities
      if result[:started].empty? && result[:stopped].empty?
        Procodile.log nil, "system", "Process concurrency looks good"
      else
        unless result[:started].empty?
          Procodile.log nil, "system", "Concurrency check started #{result[:started].map(&:description).join(', ')}"
        end

        unless result[:stopped].empty?
          Procodile.log nil, "system", "Concurrency check stopped #{result[:stopped].map(&:description).join(', ')}"
        end
      end
      result
    end

    def to_hash
      {
        :started_at => @started_at ? @started_at.to_i : nil,
        :pid => ::Process.pid
      }
    end

    def messages
      messages = []
      processes.each do |process, process_instances|
        unless process.correct_quantity?(process_instances.size)
          messages << {:type => :incorrect_quantity, :process => process.name, :current => process_instances.size, :desired => process.quantity}
        end
        for instance in process_instances
          if instance.should_be_running? && instance.status != 'Running'
            messages << {:type => :not_running, :instance => instance.description, :status => instance.status}
          end
        end
      end
      messages
    end

    def add_reader(instance, io)
      @readers[io] = instance
      @signal_handler.notice
    end

    def add_instance(instance, io = nil)
      add_reader(instance, io) if io
      @processes[instance.process] ||= []
      unless @processes[instance.process].include?(instance)
        @processes[instance.process] << instance
      end
    end

    def remove_instance(instance)
      if @processes[instance.process]
        @processes[instance.process].delete(instance)
        @readers.delete(instance)
      end
    end

    private

    def watch_for_output
      Thread.new do
        buffer = {}
        loop do
          io = IO.select([@signal_handler.pipe[:reader]] + @readers.keys, nil, nil, 30)
          @signal_handler.handle

          if io
            io.first.each do |reader|
              if reader == @signal_handler.pipe[:reader]
                @signal_handler.pipe[:reader].read_nonblock(999) rescue nil
                next
              end

              if reader.eof?
                reader.close
                buffer.delete(reader)
                @readers.delete(reader)
              else
                buffer[reader] ||= ""
                buffer[reader] << reader.read_nonblock(4096)
                while buffer[reader].index("\n")
                  line, buffer[reader] = buffer[reader].split("\n", 2)
                  if instance = @readers[reader]
                    Procodile.log instance.process.log_color, instance.description, "=> ".color(instance.process.log_color) + line
                  else
                    Procodile.log nil, 'unknown', data
                  end
                end
              end
            end
          end
        end
      end
    end

    def check_instance_quantities(type = :both, processes = nil)
      {:started => [], :stopped => []}.tap do |status|
        @processes.each do |process, instances|
          next if processes && !processes.include?(process.name)

          if type == :both || type == :stopped
            if instances.size > process.quantity
              quantity_to_stop = instances.size - process.quantity
              Procodile.log nil, "system", "Stopping #{quantity_to_stop} #{process.name} process(es)"
              status[:stopped] = instances.last(quantity_to_stop).each(&:stop)
            end
          end

          if type == :both || type == :started
            if instances.size < process.quantity
              quantity_needed = process.quantity - instances.size
              Procodile.log nil, "system", "Starting #{quantity_needed} more #{process.name} process(es)"
              status[:started] = process.generate_instances(self, quantity_needed).each(&:start)
            end
          end

        end
      end
    end

    def remove_stopped_instances
      @processes.each do |_, instances|
        instances.reject! do |instance|
          if instance.stopping? && !instance.running?
            instance.on_stop
            true
          else
            false
          end
        end
      end
    end

    def remove_removed_processes
      @processes.reject! do |process, instances|
        if process.removed && instances.empty?
          if @tcp_proxy
            @tcp_proxy.remove_process(process)
          end
          true
        else
          false
        end
      end
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
