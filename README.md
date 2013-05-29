-- ABOUT GIT-LOCK --

Git was designed to be a SCM system for a distributed development set-up with hundreds of developers.
However git is also great for smaller development teams to bring their work together.

If a projects contains binary files on which the members of a projects have to work on in parallel, 
a distributed SCM system becomes hard to work with, just because binary files can't be easily merged.
Git-lock was designed to bring a locking feature for small development teams, to avoid merge conflicts of binary files.

-- BUILDING GIT-LOCK --

$ make

* Install the server: See target/server/README
* Install the client: See target/client/README


-- USING GIT-LOCK --

Git-lock consists of two components. 

* Server: The server component controls the lock of files on a central server.
* Client: Each git-lock client is able to send lock requests to the server. With several git hooks, git-lock makes
  sure, that a client can't commit changes to a file, which were not authorized by the lock server.


-- CURRENT STATUS --

Git-lock is under development and lacks of some important features (see LIMITATIONS). However everyone is welcome
to try it and to make it better.


-- LIMITATIONS --

* Not able to see which files are locked by the user or which files are locked by all other users
* No command to break locks e.g. for the admin
