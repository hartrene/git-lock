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

Git-lock consists of three components. 

* Server: The server component controls the lock of files on a central server.
* Client: Each git-lock client is able to send lock requests to the server.
* Git hooks: Git-lock makes sure that a client can't commit changes to a lock file if someone else locked the file.

## SHOW ALL AVAILABLE COMMANDS
> $ git-lock --help

## INIT GIT BARE REPOSITORY

When receiving a push to a bare repository git-lock needs to verify that all changes are valid e.g. that no locked file was pushed.
Therefore a git hook needs to be installed in all bare repositories which need to be checked before accepting a push.
As the hook needs to communication with the lock server it needs to be initialized to get and store the server details:

> $ cd $BARE_REPO_PATH

> $ git-lock init --bare

## SAMPLE INIT & LOCK FILE

* Clone an existing git repo
> $ git clone alice@192.168.0.80:/apps/git/sample.git

* Init git-lock and point it to the lock-server (stores in .git/git-lock.config)
> $ git-lock config -server 192.168.0.80 -ssh-port 22 -remote-user alice -project foo

* Tell git-lock for which version this branch will be used (optional)
This gives the opportunity to lock a file for a specific version of the development cycle. If this isn't done then git-lock will lock all files against the master release. This information gets stored on the server and must only be done ones per branch. 
> $ git-lock switch-release -release 1.1

* Lock a binary file, so that no one else can push a change of this file until the change was pushed to the shared repo
> $ git-lock lock image.png

* Unlock the file
> $ git-lock unlock image.png

* Commit the changed binary file to the shared git repo
> $ git add image.png
> $ git commit -m"changed image"

## SHOW LOCKED FILES

* Show locks of the user
> $ git-lock status

* Show locks of all users
> $ git-lock all-locks

## BREAK A LOCK ON THE SERVER

* Get the hash of the file to unlock
> $ echo "src/image.png" | md5sum | cut -f1 -d' '

* Login to the lock server and remove all files related to that hash
> $ rm $LOCK_SERVER_DIR/$PROJECT/$RELEASE/$HASH*
