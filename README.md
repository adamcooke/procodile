# Procodile 🐊

Running & deploying Ruby apps to places like [Viaduct](https://viaduct.io) & Heroku is really easy but running processes on actual servers is less fun. Procodile aims to take some the stress out of running your Ruby/Rails apps and give you some of the useful process management features you get from the takes of the PaaS providers.

Procodile is a bit like [Foreman](https://github.com/ddollar/foreman) but things run in the background and there's a supervisor which keeps an eye on your processes and will respawn them if they die or use too much memory. Just like you're used to.

Procodile works out of the box with your existing `Procfile`.

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

To start your processes, just run the `procodile start` command. By default, this will run a each of your process types once.

```
procdile start -r path/to/your/app
# Started Procodile with PID 12345
```

To see what's happening, you'll need to look at the `supervisor.log` file which you'll find in a `log` directory in the root of your application. You'll find a more colourful version of this which shows that each of your processes has been started.

```
01:55:05 system          | BananaApp started with PID 18121
01:55:05 web.1           | Started with PID 18122
01:55:05 worker.1        | Started with PID 18123
01:55:05 cron.1          | Started with PID 18124
```

Each process will also log its output into the `log` file with the name of the process as the filename. For example `log/web.1.log` will contain the STDOUT/STDERR for the `web.1` process.

The PIDs for each of the processes are stored in a `pids` dirctory also in the root of your application. It is important that this folder only contains PID files for processes managed by Procodile. Each process will have an environment variable of `PID_FILE` which contains the path to its own PID file. If you application respawns itself, you'll need to make sure you update this file to contain the new PID so that Procodile can continue to monitor the process.

### Stopping processes

To stop your proceses, just run the `procodile stop` command. This will send a `TERM` signal to each of your applications.

```
procodile stop -r path/to/your/app
# Stopping Procodile
```

The actual Procodile master process won't stop until all of its monitored processes have stopped running. This means that you won't be able to start it again until this finishes. If you need to stop the supervisor, you can do this with the `stop_supervisor` command. Doing this will leave any processes it was managing orphans and will need to be stopped/monitored manually.

```
processes stop_supervisor -r path/to/your/app
```

### Restarting processes

The most common command you'll use is `restart`. Each time your deploy your application or make changes to your code, you can restart all the processes managed by Procodile.

```
procodile restart -r path/to/your/app
# Restarting Procodile
```

Restarting processes is a tricky process and there are 4 different modes which you can choose for your processes which define exactly how Procodile will restart it.

* `term-start` (default) - this will send a TERM signal to your existing process, wait until it isn't running any longer and then start it again.
* `start-term` - this will start up a new instance of the process, wait 15 seconds and then send a TERM signal to the original process. Note: it doesn't monitor the dead process so it is important that it respects the TERM signal.
* `usr1` or `usr2` - this will simply send a USR1/USR2 signal to the process and allow it to handle its own restart. It is important that if it changes its process ID it updates the PID file. The path to the PID file is provided in the `PID_FILE` environment variable.

You can see how to choose which mode is used for your processes below.

### Getting the status

Procdile can tell you its current status by running the `status` command. Running this will tell the supervisor process to append some status information to your log file. The output looks a little bit like this:

```
02:09:07 status          | Status as at: 2016-10-16 01:09:07 UTC
02:09:07 status          | web.1 is RUNNING (pid 20200). Respawned 0 time(s)
02:09:07 status          | worker.1 is RUNNING (pid 20201). Respawned 2 time(s)
02:09:07 status          | cron.1 is STOPPED
```

### Killing everything

If you want everything to die forcefully. The `procodile kill` command will be your friend. This will look in your `pids` directory and send `KILL` signals to every process mentioned. This is why it's important that the directory is only used for Procodile managed processes. You probably won't need to use this very often.

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
# The direcory that process logs will be stored in (default is 'log')
log_root: log/processes

# The next part allows you to add configuration for each type of process
processes:
  web:
    # The number of this type of process that should be started (default is 1)
    quantity: 2
    # The mode that should be used when restart this process (default is term-start)
    restart_mode: usr2
    # The maximum number of respawns that are permitted in the respawn window (default is 5)
    max_repawns: 10
    # The size of the respawn window (in seconds) (default is 3600)
    respawn_windows: 300
```
