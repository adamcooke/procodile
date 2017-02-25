module Procodile
  module Message
    def self.parse(message)
      case message['type']
      when 'not_running'
        "#{message['instance']} is not running (#{message['status']})"
      when 'incorrect_quantity'
        "#{message['process']} only has #{message['current']} instances (should have #{message['desired']})"
      end
    end
  end
end

