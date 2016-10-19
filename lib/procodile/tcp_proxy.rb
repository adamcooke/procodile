module Procodile
  class TCPProxy

    def self.start(supervisor)
      proxy = new(supervisor)
      proxy.start
      proxy
    end

    def initialize(supervisor)
      @supervisor = supervisor
      @thread = nil
      @listeners = {}
      @stopped_processes = []
      @sp_reader, @sp_writer = IO.pipe
    end

    def start
      @supervisor.config.processes.each { |_, p| add_process(p) }
      Thread.new do
        listen
        Procodile.log nil, 'proxy', "Stopped listening on all ports"
      end
    end

    def add_process(process)
      if process.proxy?
        @listeners[TCPServer.new('127.0.0.1', process.proxy_port)] = process
        Procodile.log nil, 'proxy', "Proxying traffic on 127.0.0.1:#{process.proxy_port} to #{process.name}"
        @sp_writer.write_nonblock('.')
      end
    end

    def remove_process(process)
      @stopped_processes << process
      @sp_writer.write_nonblock('.')
    end

    def listen
      loop do
        io = IO.select([@sp_reader] + @listeners.keys, nil, nil, 30)
        if io && io.first
          io.first.each do |io|
            if io == @sp_reader
              io.read_nonblock(999)
              next
            end

            Thread.new(io.accept, io) do |client, server|
              handle_client(client, server)
            end
          end
        end

        @stopped_processes.reject do |process|
          if io = @listeners.key(process)
            Procodile.log nil, 'proxy', "Stopped proxy listener for #{process.name}"
            io.close
            @listeners.delete(io)
          end
          true
        end
      end
    rescue => e
      Procodile.log nil, 'proxy', "Exception: #{e.class}: #{e.class}"
      Procodile.log nil, 'proxy', e.backtrace[0,5].join("\n")
    end

    def handle_client(client, server)
      process = @listeners[server]
      instances = @supervisor.processes[process] || []
      if instances.empty?
        Procodile.log nil, 'proxy', "There are no processes running for #{process.name}"
      else
        instance = instances[rand(instances.size)]
        backend_socket = TCPSocket.new('127.0.0.1', instance.port) rescue nil
        if backend_socket.nil?
          Procodile.log nil, 'proxy', "Could not connect to #{instance.description}:#{instance.port}"
          return
        end
        readers = {:backend => backend_socket, :client => client}
        loop do
          io = IO.select(readers.values, nil, nil, 0.5)
          if io && io.first
            io.first.each do |io|
              readers.keys.each do |key|
                next unless readers[key] == io
                opposite_side = key == :client ? :backend : :client
                if io.eof?
                  readers[opposite_side].shutdown(Socket::SHUT_WR) rescue nil
                  readers.delete(opposite_side)
                else
                  readers[opposite_side].write(io.readpartial(1024)) rescue nil
                end
              end
            end
          end
        end
      end
    rescue => e
      Procodile.log nil, 'proxy', "Exception: #{e.class}: #{e.class}"
      Procodile.log nil, 'proxy', e.backtrace[0,5].join("\n")
    ensure
      backend_socket.close rescue nil
      client.close rescue nil
    end

  end
end
