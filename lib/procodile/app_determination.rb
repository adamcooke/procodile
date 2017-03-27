module Procodile
  #
  # This class is responsible for determining which application should be
  # sued
  #
  class AppDetermination

    # Start by creating an determination ased on the root and procfile that has been provided
    # to us by the user (from --root and/or --procfile)
    def initialize(pwd, given_root, given_procfile, given_environment, global_options = {})
      @pwd = pwd
      @given_root = given_root
      @given_procfile = given_procfile
      @given_environment = given_environment
      @global_options = global_options
      calculate
    end

    # Return the environment
    def environment
      @given_environment || @environment || 'production'
    end

    # Return the root directory
    def root
      @root
    end

    # Return the procfile
    def procfile
      @procfile
    end

    # Return the user that we must be executing as if not current user
    def user
      @user
    end

    # Should this be reexeced
    def reexec?
      @reexec == true
    end

    # Are we in an app's directory?
    def in_app_directory?
      @in_app_directory == true
    end

    # If we have a root and procfile, we're all good
    def unambiguous?
      !!(@root && @procfile)
    end

    def ambiguous?
      !unambiguous?
    end

    # Choose which of the ambiguous options we want to choose
    def set_app(id)
      @app_id = id
      find_root_and_procfile_from_options(@global_options)
    end

    # Return an hash of possible options to settle the ambiguity
    def app_options
      if ambiguous?
        hash = {}
        @global_options.each_with_index { |option, i| hash[i] = option['name'] || option['root'] }
        hash
      else
        {}
      end
    end

    private

    def calculate
      # Try and find something using the information that has been given to us by the user
      find_root_and_procfile(@pwd, @given_root, @given_procfile)
      if ambiguous?
        # Otherwise, try and use the global config we have been given
        find_root_and_procfile_from_options(@global_options)
      else
        # Try to load additional global details on to the existing app
        if @root && options = global_options_for_path(@root)
          add_global_options(options)
        end
      end
    end

    def find_root_and_procfile(pwd, root, procfile)
      if root && procfile
        # The user has provided both the root and procfile, we can use these
        @root = expand_path(root)
        @procfile = expand_path(procfile, @root)
      elsif root && procfile.nil?
        # The user has given us a root, we can assume they want to use the procfile
        # from the root
        @root = expand_path(root)
        @procfile = File.join(@root, 'Procfile')
      elsif root.nil? && procfile
        # The user has given us a procfile but no root. We will assume the procfile
        # is in the root of the directory
        @procfile = expand_path(procfile)
        @root = File.dirname(@procfile)
      else
        # The user has given us nothing. We will check to see if there's a Procfile
        # in the root of our current pwd
        if File.file?(File.join(pwd, 'Procfile'))
          # If there's a procfile in our current pwd, we'll look at using that.
          @procfile = File.join(pwd, 'Procfile')
          @root = File.dirname(@procfile)
          @in_app_directory = true
        end
      end
    end

    def find_root_and_procfile_from_options(options)
      if options.is_a?(Hash)
        # Use the current hash
        find_root_and_procfile(@pwd, options['root'], options['procfile'])
        add_global_options(options)
      elsif options.is_a?(Array)
        # Global options is provides a list of apps. We need to know which one of
        # these we should be looking at.
        if @app_id
          find_root_and_procfile_from_options(options[@app_id])
        end
      end
    end

    def global_options_for_path(root)
      root = expand_path(root)
      if @global_options.is_a?(Hash) && @global_options['root'] && expand_path(@global_options['root']) == root
        @global_options
      elsif @global_options.is_a?(Array) && option = @global_options.select { |o| o['root'] && expand_path(o['root']) == root }.first
        option
      else
        nil
      end
    end

    def add_global_options(options)
      @user = options['user'] if options['user']
      @reexec = options['user_reexec'] if options['user_reexec']
      @environment = options['environment'] if options['environment']
    end

    def expand_path(path, root = nil)
      # Remove trailing slashes for normalization
      path = path.gsub(/\/\z/, '')
      if path =~ /\//
        # If the path starts with a /, it's absolute. Do nothing.
        path
      else
        # Otherwise, if there's a root provided, it should be from the root
        # of that otherwise from the root of the current directory.
        root ? File.join(root, path) : File.join(@pwd, path)
      end
    end

  end
end
