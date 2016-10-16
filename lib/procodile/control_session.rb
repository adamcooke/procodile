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
        Procodile.log nil, 'control', "Received stop command"
        public_send(command, options)
      else
        "404 Invaid command"
      end
    end

    def stop(options)
      @supervisor.stop
      "200"
    end

    def restart(options)
      @supervisor.restart
      "200"
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
