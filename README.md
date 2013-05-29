# ABOUT GIT-LOCK

Git was designed to be a SCM system for a distributed development set-up with hundreds of developers.
However git is also great for smaller development teams to bring their work together.

If a projects contains binary files on which the members of a projects have to work on in parallel, 
a distributed SCM system becomes hard to work with, just because binary files can't be easily merged.
Git-lock was designed to bring a locking feature for small development teams, to avoid merge conflicts of binary files.

# BUILDING GIT-LOCK

> $ make

* Install the server: See target/server/README
* Install the client: See target/client/README


# USING GIT-LOCK

Git-lock consists of two components. 

* Server: The server component controls the lock of files on a central server.
* Client: Each git-lock client is able to send lock requests to the server. With several git hooks, git-lock makes
  sure, that a client can't commit changes to a file, which were not authorized by the lock server.

## Sample

Clone an existing git repo (step omitted)
Init git-lock and point it to the lock-server
> $ git-lock init -server 192.168.0.80 -ssh-port 22 -remote-user dirk -project radadmin -release 0.1

Lock a binary file, so that no one else can edit this file until the change was committed to the shared repo
> $ git-lock lock image.png

Unlock the file
> $ git-lock unlock image.png

Commit the changed binary file and the lock-server change-signature to the shared git repo (steps omitted)

## CURRENT STATUS

Git-lock is under development and lacks of some important features (see LIMITATIONS). However everyone is welcome
to try it and to make it better.


## LIMITATIONS

* Not able to see which files which are locked by the user or to see which files are locked by all other users
* No command to break locks e.g. for the admin
