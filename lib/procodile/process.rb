require 'procodile/instance'

module Procodile
  class Process

    attr_reader :name
    attr_reader :command
    attr_reader :config

    def initialize(config, name, command, options = {})
      @config = config
      @name = name
      @command = command
      @options = options
    end

    #
    # Return the color for this process
    #
    def log_color
      @options['log_color'] || 0
    end

    #
    # How many instances of this process should be started
    #
    def quantity
      @options['quantity'] || 1
    end

    #
    # The maximum number of times this process can be respawned in the given period
    #
    def max_respawns
      @options['max_respawns'] ? @options['max_respawns'].to_i : 5
    end

    #
    # The respawn window. One hour by default.
    #
    def respawn_window
      @options['respawn_window'] ? @options['respawn_window'].to_i : 3600
    end

    #
    # Defines how this process should be restarted
    #
    # start-term = start new instances and send term to children
    # usr1 = just send a usr1 signal to the current instance
    # usr2 = just send a usr2 signal to the current instance
    # term-start = stop the old instances, when no longer running, start a new one
    #
    def restart_mode
      @options['restart_mode'] || 'term-start'
    end

    #
    # Generate an array of new instances for this process (based on its quantity)
    #
    def generate_instances
      quantity.times.map { |i| Instance.new(self, i + 1) }
    end

  end
end
