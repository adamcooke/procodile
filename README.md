# Procodile 🐊

Running & deploying Ruby apps to places like [Viaduct](https://viaduct.io) & Heroku is really easy but running processes on actual servers is less fun. Procodile aims to take some the stress out of running your Ruby/Rails apps and give you some of the useful process management features you get from the takes of the PaaS providers.

Procodile is a bit like [Foreman](https://github.com/ddollar/foreman) but things run in the background and there's a supervisor which keeps an eye on your processes and will respawn them if they die or use too much memory. Just like you're used to.

Procodile works out of the box with your existing `Procfile`.

![Screenshot](https://share.adam.ac/16/cAZRKUM7.png)

## Installing

To get started, just install the Procodile gem on your server:

```
[sudo] gem install procodile
```

Or, if you'd prefer you can just put it in your `Gemfile`.

```ruby
gem 'procodile', '~> 1.0.0'
```

## Configuring your application

To start, you'll need a normal `Procfile` with the some names & commands of the type of processes that you wish to run.

```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake app:worker
cron: bundle exec rake app:cron
```

To test things, you don't need any more than this. We'll explore how to make additional configuration a little later on.

## Using Procodile

### Starting processes

To start your processes, just run the `procodile start` command. By default, this will run each of your process types once.

```
procdile start -r path/to/your/app
# Started Procodile with PID 12345
```

The `-r` option specifies the root of your application. If you don't provide one, your current working directory will be used.

To see what's happening, you'll need to look at the `procodile.log` file which you'll in the root of your application. You'll find a more colourful version of this which shows that each of your processes has been started.

```
18:12:39 system          | BananaApp supervisor started with PID 47052
18:12:39 control         | Listening at /opt/apps/banana-app/tmp/pids/supervisor.sock
18:12:39 web.1           | Started with PID 47080
18:12:39 web.2           | Started with PID 47081
18:12:39 worker.1        | Started with PID 47082
18:12:39 cron.1          | Started with PID 47083
```

By default, each process's STDOUT and STDERR will be reported back to your `procodile.log`.

The PIDs for each of the processes are stored in a `pids` dirctory also in the root of your application. It is important that this folder only contains PID files for processes managed by Procodile. Each process will have an environment variable of `PID_FILE` which contains the path to its own PID file. If you application respawns itself, you'll need to make sure you update this file to contain the new PID so that Procodile can continue to monitor the process.

If you only wish to start a certain type (or types) of process. You can pass the `-p` option with a list of types to start.

```
procodile start -p web,worker
```

#### Additional options for start

* `-f` or `--foreground` - this will keep the Procodile application in the foreground rather than running it in the background. If you CTRL+C while running in the foreground, all processes will be stopped.
* `--clean` - this will remove the contents of your `pids` directory before starting. This avoids the supervisor picking up any old processes and managing them when it shouldn't.
* `-b` or `--brittle` - when enabled, if a single process dies, rather than respawning, all processes will be stopped and the supervisor shutdown.
* `-d` or `--dev` - this is the same as specifying `--foreground` and `--brittle`. It's ideal when you want to run your application in the foreground when developing it because processes with issues won't just be started blindly.

### Stopping processes

To stop your proceses, just run the `procodile stop` command. This will send a `TERM` signal to each of your applications.

```
procodile stop -r path/to/your/app
# Stopping web.1 (PID: 86780)
# Stopping worker,1 (PID: 86781)
# Stopping cron.1 (PID: 86782)
```

If you only wish to stop a certain process or type of process you can pass the `-p` option with a list of process types or names. In this example, it will stop `web.3` and all worker processes.

```
procodile stop -p web.3,worker
# Stopping web.3 (PID: 86780)
# Stopping worker.1 (PID: 86781)
# Stopping worker.2 (PID: 86782)
```

### Restarting processes

The most common command you'll use is `restart`. Each time your deploy your application or make changes to your code, you can restart all the processes managed by Procodile.

```
procodile restart -r path/to/your/app
# Restarting web.1 (PID: 87214)
# Restarting worker.1 (PID: 87215)
# Restarting cron.1 (PID: 87216)
```

Restarting processes is a tricky process and there are 4 different modes which you can choose for your processes which define exactly how Procodile will restart it.

* `term-start` (default) - this will send a TERM signal to your existing process, wait until it isn't running any longer and then start it again.
* `start-term` - this will start up a new instance of the process, wait 15 seconds and then send a TERM signal to the original process. Note: it doesn't monitor the dead process so it is important that it respects the TERM signal.
* `usr1` or `usr2` - this will simply send a USR1/USR2 signal to the process and allow it to handle its own restart. It is important that if it changes its process ID it updates the PID file. The path to the PID file is provided in the `PID_FILE` environment variable.

As with `stop`, you can pass `-p` to define which types of processes are restarted when you run the command.

### Getting the status

Procdile can tell you its current status by running the `status` command. This will show the status for all processes that are being supervised by Procodile.

![Screenshot](https://share.adam.ac/16/NJBJBczv.png)

### Reloading configuration

If you make changes to your `Procfile` or `Procfile.options` files you can push these updates into the running supervisor using the `reload_config` command.

* If you increase the quantity of a process, new processes will be started.
* If you decrease the quantity of a process, processes will be stopped.
* If you change a command, the old command will continue to run until you next `restart`.
* Changes to `app_name`, `log_path` and `pid_root` will not be updated until the supervisor is restarted.

### Killing everything

If you want everything to die forcefully. The `procodile kill` command will be your friend. This will look in your `pids` directory and send `KILL` signals to every process mentioned. This is why it's important that the directory is only used for Procodile managed processes. You shouldn't need to use this very often.

```
procodile kill -r path/to/your/app
# Sent KILL to 19313 (cron.1)
# Sent KILL to 19249 (supervisor)
# Sent KILL to 19314 (web.1)
# Sent KILL to 19312 (worker.1)
```

## Futher configuration

Now... until this point you were just using the defaults for everything. If you want to add some fine tuning to how Procodile treats your application, you can create `Procfile.options` file in the root of your application. The example belows shows a full example of all the options available. You can skip any of these as appropriate:

```
# The name of the application as shown on the console (default is 'Procodile')
app_name: Llama Kit
# The directory that all PIDs will be stored in (default is 'pids')
pid_root: tmp/procodile-pids
# The direcory that the procodile log file will be stored (default is 'procodile.log')
log_path: log/procodile.log

# The next part allows you to add configuration for each type of process
processes:
  web:
    # The number of this type of process that should be started (default is 1)
    quantity: 2
    # The path to store STDOUT/STDERR output for this process (default is to store in the procodile log)
    log_path: log/processs/web.log
    # The mode that should be used when restart this process (default is term-start)
    restart_mode: usr2
    # The maximum number of respawns that are permitted in the respawn window (default is 5)
    max_repawns: 10
    # The size of the respawn window (in seconds) (default is 3600)
    respawn_windows: 300
```
