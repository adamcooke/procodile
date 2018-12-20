require 'yaml'
require 'fileutils'
require 'procodile/error'
require 'procodile/process'

module Procodile
  class Config

    COLORS = [35, 31, 36, 32, 33, 34]

    def initialize(root, procfile = nil)
      @root = root
      @procfile_path = procfile
      unless File.file?(procfile_path)
        raise Error, "Procfile not found at #{procfile_path}"
      end

      # We need to check to see if the local or options
      # configuration will override the root that we've been given.
      # If they do, we can throw away any reference to the one that the
      # configuration was initialized with and start using that immediately.
      if new_root = (local_options['root'] || options['root'])
        @root = new_root
      end

      FileUtils.mkdir_p(pid_root)

      @processes = process_list.each_with_index.each_with_object({}) do |((name, command), index), hash|
        hash[name] = create_process(name, command, COLORS[index.divmod(COLORS.size)[1]])
      end

      @loaded_at = Time.now
    end

    def reload
      @process_list = nil
      @options = nil
      @process_options = nil
      @local_options = nil
      @local_process_options = nil
      @loaded_at = nil

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
      @loaded_at = Time.now
    end

    def root
      @root
    end

    def loaded_at
      @loaded_at
    end

    def user
      local_options['user'] || options['user']
    end

    def app_name
      @app_name ||= local_options['app_name'] || options['app_name'] || 'Procodile'
    end

    def console_command
      local_options['console_command'] || options['console_command']
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
      (options['env'] || {}).merge(local_options['env'] || {})
    end

    def pid_root
      File.expand_path(local_options['pid_root'] || options['pid_root'] || 'pids', self.root)
    end

    def supervisor_pid_path
      File.join(pid_root, 'procodile.pid')
    end

    def log_path
      log_path = local_options['log_path'] || options['log_path']
      if log_path
        File.expand_path(log_path, self.root)
      elsif log_path.nil? && self.log_root
        File.join(self.log_root, 'procodile.log')
      else
        File.expand_path("procodile.log", self.root)
      end
    end

    def log_root
      if log_root = (local_options['log_root'] || options['log_root'])
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
