module Procodile
  module Rbenv

    #
    # If procodile is executed through rbenv it will pollute our environment which means that
    # any spawned processes will be invoked with procodile's ruby rather than the ruby that
    # the application wishes to use
    #
    def self.without(&block)
      previous_environment = ENV.select { |k,v| k =~ /\A(RBENV\_)/ }
      if previous_environment.size > 0
        previous_environment.each { |key, value| ENV[key] = nil }
        previous_environment['PATH'] = ENV['PATH']
        ENV['PATH'] = ENV['PATH'].split(':').select { |p| !(p =~ /\.rbenv\/versions/) }.join(':')
      end
      yield
    ensure
      previous_environment.each do |key, value|
        ENV[key] = value
      end
    end

  end
end
