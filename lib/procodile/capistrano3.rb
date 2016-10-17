namespace :procodile do
  desc 'Start procodile processes'
  task :start do
    on roles(fetch(:procodile_roles, [:app])) do
      execute procodile_command(:start)
    end
  end

  desc 'Stop procodile processes'
  task :stop do
    on roles(fetch(:procodile_roles, [:app])) do
      execute procodile_command(:stop)
    end
  end

  desc 'Restart procodile processes'
  task :restart do
    on roles(fetch(:procodile_roles, [:app])) do
      execute procodile_command(:restart)
    end
  end

  after 'deploy:start', "procodile:start"
  after 'deploy:stop', "procodile:stop"
  after 'deploy:restart', "procodile:restart"

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
