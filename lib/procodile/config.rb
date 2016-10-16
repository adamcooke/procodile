require 'yaml'
require 'procodile/error'
require 'procodile/process'

module Procodile
  class Config

    COLORS = [35, 31, 36, 32, 33, 34]

    attr_reader :root

    def initialize(root)
      @root = root
      unless File.exist?(procfile_path)
        raise Error, "Procfile not found at #{procfile_path}"
      end

      FileUtils.mkdir_p(pid_root)
      FileUtils.mkdir_p(log_root)
    end

    def app_name
      options['app_name'] || 'Procodile'
    end

    def processes
      process_list.each_with_index.each_with_object({}) do |((name, command), index), hash|
        options = {'log_color' => COLORS[index.divmod(COLORS.size)[1]]}.merge(process_options[name] || {})
        hash[name] = Process.new(self, name, command, options)
      end
    end

    def process_list
      @processes ||= YAML.load_file(procfile_path)
    end

    def options
      @options ||= File.exist?(options_path) ? YAML.load_file(options_path) : {}
    end

    def process_options
      @process_options ||= options['processes'] || {}
    end

    def pid_root
      File.expand_path(options['pid_root'] || 'pids', @root)
    end

    def log_root
      File.expand_path(options['log_root'] || 'log', @root)
    end

    private

    def procfile_path
      File.join(@root, 'Procfile')
    end

    def options_path
      File.join(@root, 'Procfile.options')
    end

  end
end
