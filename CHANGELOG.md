# Changelog

## v1.0.5

* Adds a system-wide configuration file which can contain a default root directory and the user that much execute the command
* Sets a `PROC_NAME` environment variable so the process knows its name (perhaps to use in a log entry)
* If a process is restarted using USR1/USR2 update the tag to match supervisor's at the time.

## v1.0.4

* Adds a proxy for development use (see docs)
* Adds support for environment variables that can be set on a per-process basis. Just add an `env` hash.
* Removes `--brittle` option and replaces it with `--no-respawn`.
* Add process tagging so instances can be tagged with a version (or whatever)
* Process IDs will now increase upto a maximum of 10000 at which point they will circle back to 1 whenever processes are restarted (except when using usr1 or usr2 restart modes). This allows old disgarded processes to remain monitored until they are finally fully dead.
* Sets the name of the procodile supervisor process to `[procodile] App Name (root)`
* Removes `stop_supervisor` method. The supervisor can only be stopped by sending it a TERM signal manually or through `stop --stop-supervisor`
* Changes to `start`. By default, this will now start the supervisor if it's not running and then any processes required. To just start the supervisor, you can use `start --no-processes` and to avoid the behaviour where the supervisor is started when it's not running you can pass `--no-supervisor`.
* Running `start --foreground` will now fail if the start command is working with an already running supervisor.
* Fixes potential issue where the output can hang waiting for data from a process.
* Support for removing processes from the Procfile while supervisor is running

## v1.0.3

* The status output will show the times that the supervisor and all processes were last started.
* The supervisor process will remain running until explicitly stopped. It can be stopped using the `stop_supervisor` command or automatically when all processes have stopped. You can add `--stop-when-none` to the `start` command or pass `--stop-supervisor` to the `stop` command.
* Adds support for a `Procfile.local` to allow configuration to be overriden without making changes to `Procfile.options`. This allows for things like process quantity to be adjusted on a per installation basis without worrying about changes made in the repository.
* Fixes issue where restarting a process would result in the logs disappearing when piped back.
* Adds a `--json` option for the `status` command to return status information as a JSON hash.
* Adds `help` command which shows a list of all supported commands for procodile.
* Show the current root directory in the status output.
* Moved capistrano recipes into their own repository/gem (`procodile-capistrano`).
* Adds `APP_ROOT` environment variable that is provided to all spawned processes with the root of the application in.
* Support for defining environment variables in the `Procfile.options` (or `Procfile.local`) files which will be provided to the processes.
* `reload_config` renamed to `reload` and will no longer check concurrency of processes.
* Added `check_concurrency` command to check the concurrency of the running processes compared to the configured options.
