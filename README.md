# Procodile 🐊

Running & deploying Ruby apps to places like [Viaduct](https://viaduct.io) & Heroku is really easy but running processes on actual servers is less fun. Procodile aims to take some the stress out of running your Ruby/Rails apps and give you some of the useful process management features you get from the takes of the PaaS providers.

Procodile is a bit like [Foreman](https://github.com/ddollar/foreman) but things are designed to run in the background (as well as the foreground if you prefer) and there's a supervisor which keeps an eye on your processes and will respawn them if they die. It also handles orchesting restarts whenever you deploy new code so.

Procodile works out of the box with your existing `Procfile`.

![Screenshot](https://share.adam.ac/16/cAZRKUM7.png)

## Installing

To get started, just install the Procodile gem on your server (or local machine). It is recommended to install Procodile as a system gem rather than as part of an existing bundle.

```
$ [sudo] gem install procodile
```

Check everything is working OK by running `procodile`. This will show you the help menu.

```
$ procodile
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

The following examples will assume that you have entered the root directory of your application and there's a `Procfile` there.

### Starting processes

To start your processes, just run the `procodile start` command. By default, this will run each of your process types once. If this is your first time running Procodile, it's probably best to start things in the foreground so you can easily see what's going on.

```
$ procodile start --foreground
```

Your Procfile will now be parsed and the processes started. The output will look a little bit like this:

```
18:12:39 system          | BananaApp supervisor started with PID 47052
18:12:39 control         | Listening at /opt/apps/banana-app/tmp/pids/supervisor.sock
18:12:39 web.1           | Started with PID 47080
18:12:39 web.2           | Started with PID 47081
18:12:39 worker.1        | Started with PID 47082
18:12:39 cron.1          | Started with PID 47083
```

Once everything is running, you can press CTRL+C which will terminate all the processes. To run the commands in the backgrond, just goahead and run the start command without the `-f`. When you do this, all the log output you saw previously will be saved into a `procodile.log` file in the root of your application.

#### Additional options for start

* `-p` or `--processes` - by default all process types will be started, if you'd prefer to only start  certain processes you can pass a list here. For example `web,worker,cron`.
* `-f` or `--foreground` - this will keep the Procodile application in the foreground rather than running it in the background. If you CTRL+C while running in the foreground, all processes will be stopped.
* `--clean` - this will remove the contents of your `pids` directory before starting. This avoids the supervisor picking up any old processes and managing them when it shouldn't.
* `-b` or `--brittle` - when enabled, if a single process dies, rather than respawning, all processes will be stopped and the supervisor shutdown.
* `--stop-when-none` - when enabled, the supervisor process will be stopped when there are no processes monitored.
* `-d` or `--dev` - this is the same as specifying `--foreground`, `--brittle` and `--stop-when-none`. It's ideal when you want to run your application in the foreground when developing it because processes with issues won't just be started blindly.

### Stopping processes

To stop your proceses, just run the `procodile stop` command. This will send a `TERM` signal to each of your applications.

```
$ procodile stop
```

#### Stopping only certain processes

If you only wish to stop a certain process or type of process you can pass the `--processes` option with a list of process types or names. In this example, it will stop `web.3` and all worker processes.

```
$ procodile stop --processes web.3,worker
```

#### Additional options for stop

* `-p` or `--processes` - by default all process types will be stopped, if you'd prefer to only stop certain processes you can pass a list here. You can stop individual types or instances. For example `web.2,worker` to stop the web.2 process and all worker processes.
* `-s` or `--stop-supervisor` - when stopping, the supervisor will remain running but if you'd like to stop it when all processes are stopped you can pass this option.

### Restarting processes

The most common command you'll use is `restart`. Each time your deploy your application or make changes to your code, you can restart all the processes managed by Procodile.

```
$ procodile restart
```

Restarting processes is a tricky process and there are 4 different modes which you can choose for your processes which define exactly how Procodile will restart it.

* `term-start` (default) - this will send a TERM signal to your existing process, wait until it isn't running any longer and then start it again.
* `start-term` - this will start up a new instance of the process, wait 15 seconds and then send a TERM signal to the original process. Note: it doesn't monitor the dead process so it is important that it respects the TERM signal.
* `usr1` or `usr2` - this will simply send a USR1/USR2 signal to the process and allow it to handle its own restart. It is important that if it changes its process ID it updates the PID file. The path to the PID file is provided in the `PID_FILE` environment variable.

#### Additional options for restart

* `-p` or `--processes` - by default all process types will be restarted, if you'd prefer to only restart certain processes you can pass a list here. You can restart individual types or instances. For example `web.2,worker` to restart the web.2 process and all worker processes.

### Getting the status

Procdile can tell you its current status by running the `status` command. This will show the status for all processes that are being supervised by Procodile.

```
$ procodile status
```

#### Additional options for stop

* `--json` - returns the status information as a JSON hash

### Reloading configuration

If you make changes to your `Procfile` or `Procfile.options` files you can push these updates into the running supervisor using the `reload` command.

* If you increase or decrease the quantity of processes required, they will be changed the next you start/restart a process or when you run `check_concurrency`.
* If you change a command, the old command will continue to run until you next `restart`.
* Changes to environment variables will apply next time a process is started.
* Changes to the restart mode of a process will apply straight away so this will be used on the next restart.
* Changes to `app_name`, `log_path` and `pid_root` will not be updated until the supervisor is restarted.

```
$ procodile reload
```

### Checking process concurrency

Sometimes you need to change the quantity of processes that are running in situ. Running `check_concurrency` will compare the running process quantity with that in your configuration and start/stop processes so they match.

```
$ procodile check_concurrency
```

#### Additional options for check concurrency

* `--no-reload` - by default, running `check_concurrency` will reload the configuration before checking. You can pass this option to simply check concurrency against that data in memory from the last time the config was loaded.

### Killing everything

If you want everything to die forcefully. The `procodile kill` command will be your friend. This will look in your `pids` directory and send `KILL` signals to every process mentioned. This is why it's important that the directory is only used for Procodile managed processes. You shouldn't need to use this very often.

```
$ procodile kill
```

## PID files

The PIDs for each of the processes are stored in a `pids` dirctory also in the root of your application. It is important that this folder only contains PID files for processes managed by Procodile. Each process will have an environment variable of `PID_FILE` which contains the path to its own PID file. If you application respawns itself, you'll need to make sure you update this file to contain the new PID so that Procodile can continue to monitor the process.

## Application Root Path

In these examples, we've assumed that you're current within root directory of your application however you can use the `--root` (or `-r`) option to specify the root directory.

```
$ procodile start --root /opt/apps/banana-app
```

If you deploy your application into a release directory and then symlink into a `current` directory, you should always use this option otherwise Procodile will resolve the root into the specific release directory and restarts will always just restart the same directory that you were in when you started the first time.

If you need to provide the application root directory to your processes, you can use the `APP_ROOT` environment variable which will pass through whatever you enter here.

## Futher configuration

Now... until this point you were just using the defaults for everything. If you want to add some fine tuning to how Procodile treats your application, you can create `Procfile.options` file in the root of your application. The example belows shows a full example of all the options available. You can skip any of these as appropriate:

```yaml
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
    respawn_window: 300
    # The signal to send to terminate this process (default is TERM)
    term_signal: INT

# You can add environment variables which should be provided to any spawned processes
env:
  RAILS_ENV: production
  SECRET_KEY_BASE: XXX
```

It is recommended to create and commit a `Procfile.options` file for your application. If changes are needed (for example to increase or decrease a process quantity), a `Procfile.local` file can be added on a per-installation basis to change this.

## Deploying with Capistrano

Recipes for deploying with Capistrano can be found on [the procodile-capistrano page](https://github.com/adamcooke/procodile-capistrano).
