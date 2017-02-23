require 'json'
require 'procodile/version'

module Procodile
  class ControlSession

    def initialize(supervisor, client)
      @supervisor = supervisor
      @client = client
    end

    def receive_data(data)
      command, options = data.split(/\s+/, 2)
      options = JSON.parse(options)
      if self.class.instance_methods(false).include?(command.to_sym) && command != 'receive_data'
        begin
          public_send(command, options)
        rescue Procodile::Error => e
          Procodile.log nil, 'control', "Error: #{e.message}".color(31)
          "500 #{e.message}"
        end
      else
        "404 Invaid command"
      end
    end

    def start_processes(options)
      instances = @supervisor.start_processes(options['processes'], :tag => options['tag'])
      "200 " + instances.map(&:to_hash).to_json
    end

    def stop(options)
      instances = @supervisor.stop(:processes => options['processes'], :stop_supervisor => options['stop_supervisor'])
      "200 " + instances.map(&:to_hash).to_json
    end

    def restart(options)
      instances = @supervisor.restart(:processes => options['processes'], :tag => options['tag'])
      "200 " + instances.map { |a| a.map { |i| i ? i.to_hash : nil } }.to_json
    end

    def reload_config(options)
      @supervisor.reload_config
      "200"
    end

    def check_concurrency(options)
      result = @supervisor.check_concurrency(:reload => options['reload'])
      result = result.each_with_object({}) { |(type, instances), hash| hash[type] = instances.map(&:to_hash) }
      "200 #{result.to_json}"
    end


    def status(options)
      instances = {}
      @supervisor.processes.each do |process, process_instances|
        instances[process.name] = []
        for instance in process_instances
          instances[process.name] << instance.to_hash
        end
      end

      processes = @supervisor.processes.keys.map(&:to_hash)
      result = {
        :version => Procodile::VERSION,
        :root => @supervisor.config.root,
        :environment => @supervisor.config.environment,
        :app_name => @supervisor.config.app_name,
        :supervisor => @supervisor.to_hash,
        :instances => instances,
        :processes => processes,
        :environment_variables => @supervisor.config.environment_variables
      }
      "200 #{result.to_json}"
    end

  end
end
