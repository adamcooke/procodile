require 'socket'
require 'procodile/control_session'

module Procodile
  class ControlServer

    def self.start(supervisor)
      Thread.new do
        socket = ControlServer.new(supervisor)
        socket.listen
      end
    end

    def initialize(supervisor)
      @supervisor = supervisor
    end

    def listen
      socket = UNIXServer.new(@supervisor.config.sock_path)
      Procodile.log nil, 'control', "Listening at #{@supervisor.config.sock_path}"
      loop do
        client = socket.accept
        session = ControlSession.new(@supervisor, client)
        while line = client.gets
          if response = session.receive_data(line.strip)
            client.puts response
          end
        end
        client.close
      end
    ensure
      FileUtils.rm_f(@supervisor.config.sock_path)
    end

  end
end
