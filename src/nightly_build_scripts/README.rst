OctoPi Nightly Build Scripts
============================

The scripts in this folder are used to build OctoPi nightly.
The are also two scripts that help you checkout mirrors of the git repos used in the build, the cloning would not be done remotely fromt he github repos.

* build_local_mirrors - Run this once to clone repos in to /var/www/git folder .
* update_git_mirrors - Run this before each build in order to update the mirrors.
* octopi_nightly_build - Run this to build OctoPi, can be set to run with sudo without a password so an executor like Jenkins can run it.


