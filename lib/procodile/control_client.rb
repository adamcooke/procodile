require 'json'
require 'socket'

module Procodile
  class ControlClient

    def initialize(sock_path, &block)
      @socket = UNIXSocket.new(sock_path)
      if block_given?
        begin
          block.call(self)
        ensure
          disconnect
        end
      end
    end

    def self.run(sock_path, command, options = {})
      socket = self.new(sock_path)
      socket.run(command, options)
    ensure
      socket.disconnect rescue nil
    end

    def run(command, options = {})
      @socket.puts("#{command} #{options.to_json}")
      code, reply = @socket.gets.strip.split(/\s+/, 2)
      if code.to_i == 200
        if reply && reply.length > 0
          JSON.parse(reply)
        else
          true
        end
      else
        raise Error, "Error from control server: #{code} (#{reply.inspect})"
      end
    end

    def disconnect
      @socket.close rescue nil
    end

    private

    def parse_response(data)
      code, message = data.split(/\s+/, 2)
    end

  end
end
