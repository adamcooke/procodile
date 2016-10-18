# Procodile 🐊

Running & deploying Ruby apps to places like [Viaduct](https://viaduct.io) & Heroku is really easy but running processes on actual servers is less fun. Procodile aims to take some the stress out of running your Ruby/Rails apps and give you some of the useful process management features you get from the takes of the PaaS providers.

Procodile is a bit like [Foreman](https://github.com/ddollar/foreman) but things are designed to run in the background (as well as the foreground if you prefer) and there's a supervisor which keeps an eye on your processes and will respawn them if they die. It also handles orchesting restarts whenever you deploy new code so.

Procodile works out of the box with your existing `Procfile`.

* [Read documentation](https://github.com/adamcooke/procodile/wiki)
* [View on RubyGems](https://rubygems.org/gems/procodile)
* [Check the CHANGELOG](https://github.com/adamcooke/procodile/blob/master/CHANGELOG.md)

![Screenshot](https://share.adam.ac/16/cAZRKUM7.png)
