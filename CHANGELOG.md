# Changelog

## v1.1.0

* The status output will show the times that the supervisor and all processes were last started.
* The supervisor process will remain running until explicitly stopped. It can be stopped using the `stop_supervisor` command or automatically when all processes have stopped. You can add `--stop-when-none` to the `start` command or pass `--stop-supervisor` to the `stop` command.
* Adds support for a `Procfile.concurrency` to allow process quantities to be changed without needing to make changes to `Procfile.options` which might be checked into a repository as it contains application specific configuration where as the concurrency for a process might be environment specific.
