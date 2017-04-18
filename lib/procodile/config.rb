require 'yaml'
require 'fileutils'
require 'procodile/error'
require 'procodile/process'

module Procodile
  class Config

    COLORS = [35, 31, 36, 32, 33, 34]

    attr_reader :root
    attr_reader :environment

    def initialize(root, environment = nil, procfile = nil)
      @root = root
      @environment = environment || 'production'
      @procfile_path = procfile
      unless File.file?(procfile_path)
        raise Error, "Procfile not found at #{procfile_path}"
      end
      FileUtils.mkdir_p(pid_root)

      @processes = process_list.each_with_index.each_with_object({}) do |((name, command), index), hash|
        hash[name] = create_process(name, command, COLORS[index.divmod(COLORS.size)[1]])
      end
    end

    def reload
      @process_list = nil
      @options = nil
      @process_options = nil
      @local_options = nil
      @local_process_options = nil

      if @processes
        process_list.each do |name, command|
          if process = @processes[name]
            process.removed = false
            # This command is already in our list. Add it.
            if process.command != command
              process.command = command
              Procodile.log nil, 'system', "#{name} command has changed. Updated."
            end
            process.options = options_for_process(name)
          else
            Procodile.log nil, 'system', "#{name} has been added to the Procfile. Adding it."
            @processes[name] = create_process(name, command, COLORS[@processes.size.divmod(COLORS.size)[1]])
          end
        end

        removed_processes = @processes.keys - process_list.keys
        removed_processes.each do |process_name|
          if p = @processes[process_name]
            p.removed = true
            @processes.delete(process_name)
            Procodile.log nil, 'system', "#{process_name} has been removed to the Procfile. It will be removed when it is stopped."
          end
        end
      end
    end

    def root
      fetch(local_options['root']) || fetch(options['root']) || @root
    end

    def app_name
      @app_name ||= fetch(local_options['app_name']) || fetch(options['app_name']) || 'Procodile'
    end

    def console_command
      fetch(local_options['console_command']) || fetch(options['console_command'])
    end

    def processes
      @processes ||= {}
    end

    def process_list
      @process_list ||= load_process_list_from_file
    end

    def options
      @options ||= load_options_from_file
    end

    def process_options
      @process_options ||= options['processes'] || {}
    end

    def local_options
      @local_options ||= load_local_options_from_file
    end

    def local_process_options
      @local_process_options ||= local_options['processes'] || {}
    end

    def options_for_process(name)
      (process_options[name] || {}).merge(local_process_options[name] || {})
    end

    def environment_variables
      fetch_hash_values(options['env'] || {}).merge(fetch_hash_values(local_options['env'] || {}))
    end

    def pid_root
      @pid_root ||= File.expand_path(fetch(local_options['pid_root']) || fetch(options['pid_root']) || 'pids', self.root)
    end

    def supervisor_pid_path
      File.join(pid_root, 'procodile.pid')
    end

    def log_path
      log_path = fetch(local_options['log_path']) || fetch(options['log_path'])
      if log_path
        File.expand_path(log_path, self.root)
      elsif log_path.nil? && self.log_root
        File.join(self.log_root, 'procodile.log')
      else
        File.expand_path("procodile.log", self.root)
      end
    end

    def log_root
      if log_root = (fetch(local_options['log_root']) || fetch(options['log_root']))
        File.expand_path(log_root, self.root)
      else
        nil
      end
    end

    def sock_path
      File.join(pid_root, 'procodile.sock')
    end

    def procfile_path
      @procfile_path || File.join(self.root, 'Procfile')
    end

    def options_path
      procfile_path + ".options"
    end

    def local_options_path
      procfile_path + ".local"
    end

    private

    def create_process(name, command, log_color)
      process = Process.new(self, name, command, options_for_process(name))
      process.log_color = log_color
      process
    end

    def fetch(value, default = nil)
      if value.is_a?(Hash)
        if value.has_key?(@environment)
          value[@environment]
        else
          default
        end
      else
        value.nil? ? default : value
      end
    end

    def fetch_hash_values(hash)
      hash.each_with_object({}) do |(key, value), h|
        if value = fetch(value)
          h[key] = value
        end
      end
    end

    def load_process_list_from_file
      YAML.load_file(procfile_path)
    end

    def load_options_from_file
      File.exist?(options_path) ? YAML.load_file(options_path) : {}
    end

    def load_local_options_from_file
      File.exist?(local_options_path) ? YAML.load_file(local_options_path) : {}
    end

  end
end
