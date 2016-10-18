# Changelog

## v1.1.0

* The status output will show the times that the supervisor and all processes were last started.
* The supervisor process will remain running until explicitly stopped. It can be stopped using the `stop_supervisor` command or automatically when all processes have stopped. You can add `--stop-when-none` to the `start` command or pass `--stop-supervisor` to the `stop` command.
* Adds support for a `Procfile.local` to allow configuration to be overriden without making changes to `Procfile.options`. This allows for things like process quantity to be adjusted on a per installation basis without worrying about changes made in the repository.
* Fixes issue where restarting a process would result in the logs disappearing when piped back.
* Adds a `--json` option for the `status` command to return status information as a JSON hash.
* Adds `help` command which shows a list of all supported commands for procodile.
