require 'json'

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
          Procodile.log nil, 'control', "Received #{command} command"
          public_send(command, options)
        rescue Procodile::Error => e
          Procodile.log nil, 'control', "\e[31mError: #{e.message}\e[0m"
          "500 #{e.message}"
        end
      else
        "404 Invaid command"
      end
    end

    def stop(options)
      instances = @supervisor.stop(:processes => options['processes'])
      "200 " + instances.map(&:to_hash).to_json
    end

    def restart(options)
      instances = @supervisor.restart(:processes => options['processes'])
      "200 " + instances.map(&:to_hash).to_json
    end

    def reload_config(options)
      @supervisor.reload_config
      "200"
    end

    def stop_supervisor(options)
      @supervisor.stop_supervisor
      "200"
    end

    def status(options)
      status = {}
      for process, instances in @supervisor.processes
        status[process.name] = []
        for instance in instances
          status[process.name] << {
            :description => instance.description,
            :pid => instance.pid,
            :running => instance.running?,
            :respawns => instance.respawns,
            :command => instance.process.command
          }
        end
      end
      "200 #{status.to_json}"
    end

  end
end
