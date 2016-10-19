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

    def app_name
      @app_name ||= local_options['app_name'] || options['app_name'] || 'Procodile'
    end

    def processes
      @processes ||= {}
    end

    def process_list
      @process_list ||= YAML.load_file(procfile_path) || {}
    end

    def options
      @options ||= File.exist?(options_path) ? YAML.load_file(options_path) : {}
    end

    def process_options
      @process_options ||= options['processes'] || {}
    end

    def local_options
      @local_options ||= File.exist?(local_options_path) ? YAML.load_file(local_options_path) : {}
    end

    def local_process_options
      @local_process_options ||= local_options['processes'] || {}
    end

    def options_for_process(name)
      (process_options[name] || {}).merge(local_process_options[name] || {})
    end

    def environment_variables
      (options['env'] || {}).merge(local_options['env'] || {})
    end

    def local_environment_variables
      @local_environment_variables ||= local_options['env'] || {}
    end

    def pid_root
      @pid_root ||= File.expand_path(local_options['pid_root'] || options['pid_root'] || 'pids', @root)
    end

    def log_path
      @log_path ||= File.expand_path(local_options['log_path'] || options['log_path'] || 'procodile.log', @root)
    end

    def sock_path
      File.join(pid_root, 'procodile.sock')
    end

    private

    def procfile_path
      File.join(@root, 'Procfile')
    end

    def options_path
      File.join(@root, 'Procfile.options')
    end

    def local_options_path
      File.join(@root, 'Procfile.local')
    end

    def create_process(name, command, log_color)
      process = Process.new(self, name, command, options_for_process(name))
      process.log_color = log_color
      process
    end

  end
end
