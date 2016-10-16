# TODO

* Memory monitoring of processes. If a process uses too much memory, it should respawn it.
* Improved status output.
* Some more commenting would be nice.
* Ability to start/stop/restart individual process types.
* Improved interface to communicate from the CLI and the Supervisor. Using signals to tell it to do stuff isn't really going to cut it when we need to give it additional context from the CLI (i.e. which process should be restarted etc...). Such an interface could also be used to return the status to the CLI directly rather than having to put in a log file.
