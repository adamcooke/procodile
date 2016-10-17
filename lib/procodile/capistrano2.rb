Capistrano::Configuration.instance(:must_exist).load do

  namespace :procodile do

    task :start, :roles => fetch(:procodile_roles, [:app]) do
      run procodile_command('start')
    end

    task :stop, :roles => fetch(:procodile_roles, [:app]) do
      run procodile_command('stop')
    end

    task :restart, :roles => fetch(:procodile_roles, [:app]) do
      run procodile_command('restart')
    end

    task :status, :roles => fetch(:procodile_roles, [:app]) do
      run procodile_command('status')
    end

    after 'deploy:start', 'procodile:start'
    after 'deploy:stop', 'procodile:stop'
    after 'deploy:restart', 'procodile:restart'

    def procodile_command(command, options = "")
      binary = fetch(:procodile_binary, 'procodile')
      if processes = fetch(:processes, nil)
        options = "-p #{processes} " + options
      end
      command = "#{binary} #{command} -r #{current_path} #{options}"
      if user = fetch(:procodile_user, nil)
        "sudo -u #{user} #{command}"
      else
        command
      end
    end

  end
end
