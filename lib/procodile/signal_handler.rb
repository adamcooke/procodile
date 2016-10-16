module Procodile
  class SignalHandler

    attr_reader :pipe

    def self.queue
      Thread.main[:signal_queue] ||= []
    end

    def initialize(*signals)
      @handlers = {}
      reader, writer = IO.pipe
      @pipe = {:reader => reader, :writer => writer}
      signals.each do |sig|
        Signal.trap(sig, proc { SignalHandler.queue << sig ; notice })
      end
    end

    def start
      Thread.new do
        loop do
          handle
          sleep 1
        end
      end
    end

    def register(name, &block)
      @handlers[name] ||= []
      @handlers[name] << block
    end

    def notice
      @pipe[:writer].write_nonblock('.')
    end

    def handle
      if signal = self.class.queue.shift
        if @handlers[signal]
          @handlers[signal].each(&:call)
        end
      end
    end

  end
end
