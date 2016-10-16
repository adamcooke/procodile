require 'logger'
module Procodile

  def self.mutex
    @mutex ||= Mutex.new
  end

  def self.log(color, name, text)
    mutex.synchronize do
      text.to_s.lines.map(&:chomp).each do |message|
        output  = ""
        output += "\e[#{color}m" if color
        output += "#{Time.now.strftime("%H:%M:%S")} #{name.ljust(15, ' ')} |"
        output += "\e[0m "
        output += message
        $stdout.puts output
        $stdout.flush
      end
    end
  end

end
