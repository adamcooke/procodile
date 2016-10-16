module Procodile
  class SignalHandler

    def self.queue
      Thread.main[:signal_queue] ||= []
    end

    def initialize(*signals)
      @handlers = {}
      Thread.new do
        loop do
          if signal = self.class.queue.shift
            if @handlers[signal]
              @handlers[signal].each(&:call)
            end
          end
          sleep 1
        end
      end

      signals.each do |sig|
        Signal.trap(sig, proc { SignalHandler.queue << sig })
      end
    end

    def register(name, &block)
      @handlers[name] ||= []
      @handlers[name] << block
    end

  end
end
