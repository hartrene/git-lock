#!/bin/bash

# This file contains all git-lock client functions

# Import util functions
. "${LOCK_CLIENT_BIN_DIR}/lock-util.sh"

REMOTE_USER_PROPERTY_KEY="REMOTE_USER"
SERVER_ADDRESS_PROPERTY_KEY="SERVER_ADDRESS"
SSH_PORT_PROPERTY_KEY="SERVER_SSH_PORT"
PROJECT_PROPERTY_KEY="PROJECT"
RELEASE_PROPERTY_KEY="RELEASE"

REQUIRED_SERVER_PROPERTIES=(
	"$REMOTE_USER_PROPERTY_KEY:Which user should be used to connect to the lock server"
	"$SERVER_ADDRESS_PROPERTY_KEY:What is the address of the lock server"
	"$SSH_PORT_PROPERTY_KEY:Which ssh port should be used to connect to the lock server"
);

REQUIRED_PROPERTIES=(
	"$PROJECT_PROPERTY_KEY:What is the project you're working on"
	"$RELEASE_PROPERTY_KEY:In which release is this branch going"
);

# Prints all commands
lockClientHelp() {
	echo "-- Available git-lock commands:"
	echo "init"
	echo "  Initializes git-lock"
	echo "init --bare"
	echo "  Initializes git-lock in a bare repository"
	echo "lock [FILE]"
	echo "  Locks a file on the lock-server, so that no other user can edit this file until the lock is released (unlock)."
	echo "unlock [FILE]"
	echo "  Unlocks a previously locked file"
	echo "cancel [FILE]"
	echo "  Cancel/release a lock"
	echo "status"
	echo "  Show the project/release and all locks of the user"
	echo ""
	echo "-- Lock-server commands:"
	echo "all-locks"
	echo "  Show locks of all user"
	echo "lookup-projects"
	echo "  Logs all existing projects and releases on the lock-server"
	echo "lookup-project-dir [PROJECT]"
	echo "  Lookup of the project directory on the lock-server"
	echo "lookup-release-dir [PROJECT] [RELEASE]"
	echo "  Lookup of the release directory on the lock-server"
	echo ""
	echo "-- Configuration commands:"
	echo "properties"
	echo "  Logs all git-lock properties"
	echo "set-property"
	echo "  Sets/Overrides the given git-lock properties"
	echo "  	-project [PROJECT_NAME]"
	echo "  	-release [RELEASE_NAME]"
	echo "  	-remote-user [REMOTE_USER]"
	echo "  	-server [SERVER_ADDRESS]"
	echo "  	-ssh-port [SSH_PORT]"
	echo "switch-project [PROJECT_NAME] [RELEASE_NAME]"
	echo "  Changes the project of that branch"
	echo "switch-remote-user [REMOTE_USER]"
	echo "  Changes the lock-server username"
	echo "switch-server [SERVER_ADDRESS]"
	echo "  Changes the address of the lock-server"
	echo "switch-ssh-port [SERVER_SSH_PORT]"
	echo "  Changes the ssh port of the lock-server"
}

# Main function which dispatches calls to all lock-client functions.
# This function gets called from the shell script git-lock or it gets called directly from the unit-tests.
lockClient() {
	command="$1"
	
	# Shift the input variables so that the next function won't get the command ($2 becomes $1...)
	shift
	
	# Dispatch the incomming command to the correct function
	case "$command" in
		--help) lockClientHelp "$@";;
		init) 
			if [ "${1:-}" = "--bare" ]; then
				shift
				lockClientInitBare "$@"
			else
				lockClientInit "$@"
			fi
			;;
		create-project) lockClientCreateProject "$@";;
		lock) lockClientLock "$@";;
		unlock) lockClientUnlock "$@";;
		cancel) lockClientCancel "$@";;
		status) lockClientStatus "$@";;
		all-locks) lockClientShowAllLocks "$@";;
		
		# Commands for property manipulation
		properties) lockClientProperties "$@";;
		set-property) lockClientSetProperty "$@";;
		switch-project) lockClientSwitchProject "$@";;
		switch-remote-user) lockClientSetProperty -remote-user "$@";;
		switch-server) lockClientSetProperty -server "$@";;
		switch-ssh-port) lockClientSetProperty -ssh-port "$@";;
		
		# Commands for questioning the server
		lookup-projects) lockClientLookupServer "projects" "$@";;
		lookup-project-dir) lockClientLookupServer "project-dir" "$@";;
		lookup-release-dir) lockClientLookupServer "release-dir" "$@";;
		
		*) lockClientHelp "$@";;
	esac
}

# Lookup of lock-server details.
# lookup-project [PROJECT]: Lookup of the project directory on the lock-server
# lookup-release [PROJECT] [RELEASE]: Lookup of the release directory on the lock-server
# lookup-projects: Logs all existing projects and releases on the lock-server
#
# @return_codes 0=success 1=failure
# @return_value Project or release directory
lockClientLookupServer() {
	local lookupProperty="${1:-}"
	# Check that at least the CMD was given
	checkParameter 1 "lockClientLookupServer() [CMD]" "$lookupProperty"
	
	shift
	case "$lookupProperty" in
		project-dir)
			checkParameter 1 "lookup-project [PROJECT]" "$@"
			returnValue=$(executeOnServer lookup-project-dir "'$1'");;
		release-dir)
			checkParameter 2 "lookup-release [PROJECT] [RELEASE]" "$@"
			returnValue=$(executeOnServer lookup-release-dir "'$1'" "'$2'");;
		projects)
			returnValue=$(executeOnServer lookup-projects);;
		*)
			echo "Lookup property not found: $lookupProperty"
			exit 1;;
	esac
	
	returnCode=$?
	echo "$returnValue"
	return $returnCode
}

# Returns all git-lock properties.
#
# @return_codes 0=success 1=failure
# @return_value git-lock properties
lockClientProperties() {
	checkParameter 0 "properties" "$@"
	# Get the required properties
	needPropertyFilePath propertyFile
	local data="$(cat "$propertyFile")"
	echo "$data"
}

# Sets/Overrides git-lock properties.
#   -project [PROJECT_NAME] 
#   -release [RELEASE_NAME] 
#   -remote-user [REMOTE_USER] 
#   -server [SERVER_ADDRESS] 
#   -ssh-port [SSH_PORT]
#
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientSetProperty() {
	# Check if property file exists
	getPropertyFilePath propertyFile $PROPERTY_FILE "$@"
		
	if [ ! -e "$propertyFile" ]; then
		returnValue=$(touch "$propertyFile")
		expectSuccess "Property file couldn't be created: $returnValue" $?
		logDebug "Created git-lock properties file: $propertyFile"
	fi

	# Read all properties and save them
	while :
	do
		local propertyId="${1:-}"
		local propertyValue="${2:-}"
		
		if [ -z "$propertyId" ]; then
			break
		fi
		
		case "$propertyId" in
			-p  | -project) propertyKey="$PROJECT_PROPERTY_KEY";;
			-r  | -release) propertyKey="$RELEASE_PROPERTY_KEY";;
			-ru | -remote-user) propertyKey="$REMOTE_USER_PROPERTY_KEY";;
			-s  | -server) propertyKey="$SERVER_ADDRESS_PROPERTY_KEY";;
			-sp | -ssh-port) propertyKey="$SSH_PORT_PROPERTY_KEY";;
			*)
				echo "Error unknown property: $propertyId"
				exit 1;;
		esac
		
		if [ -z "$propertyValue" ]; then
			echo "No value given for switch$propertyId"
			exit 1
		fi
		
		writeProperty "$propertyFile" "$propertyKey" "$propertyValue"
		logInfo "Property $propertyKey was set to: $propertyValue"
		
		# Shift to the next pair of properties
		shift 2	
	done
}

# Initializes git-lock.
# Creates the project and release on the lock-server.
# Possibile to give the required properties as arguments: 
#   -project [PROJECT_NAME] 
#   -release [RELEASE_NAME] 
#   -remote-user [REMOTE_USER] 
#   -server [SERVER_ADDRESS] 
#   -ssh-port [SSH_PORT]
# If some properties were not given as arguments, it will ask to enter the missing properties.
#
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientInit() {
	logInfo "Init git-lock"
	
	# Store the parameter if some where given
	lockClientSetProperty "$@"
	
	# Ask for all missing properties
	askForAllMissingProperties
	
	# Run the server init
	lockClientCreateProject
	
	# Install hooks
	lockClientInitHooks
	
	logInfo "git-lock init done"
}

# Initializes git-lock in a bare repository.
# Possibile to give the required properties as arguments: 
#   -remote-user [REMOTE_USER] 
#   -server [SERVER_ADDRESS] 
#   -ssh-port [SSH_PORT]
# If some properties were not given as arguments, it will ask to enter the missing properties.
#
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientInitBare() {
	logInfo "Init git-lock in a bare repository"
	
	# Store the parameter if some where given
	lockClientSetProperty "$@"
	
	# Ask for all missing server properties
	askForAllMissingServerProperties
	
	# Install hooks
	lockClientInitHooks
	
	logInfo "git-lock init --bare done"
}

# Creates the project and release on the lock-server.
#
# @return_codes 0=success 1=failure
# @return_value return value from the server
lockClientCreateProject() {
	# Store the parameter if some where given
	lockClientSetProperty "$@"
	
	# Get the required properties
	needPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
	
	# Get branch
	branch=$(git branch | grep "*" | cut -d " " -f2)
	if [ "$branch" = "" ]; then
		branch="master"
	fi
			
	# Run the server init
	logDebug "Create project and release on server"
	returnValue=$(executeOnServer init-project "'$branch'" "'$project'" "'$release'")
	expectSuccess "Server wasn't able to create the project and releaes $returnValue" $?
}

# Locks a file on the lock-server, so that no other user can edit this file until the lock is released (unlock).
#
# @param FILE File to lock
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientLock() {
	checkParameter 1 "lock [FILE]" "$@"
	local fileToLock="$1"
	
	# Check if the file exists
	expectFileExists "$fileToLock" "File to lock doesn't exist: $fileToLock"
	
	# Get the required properties
	needPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
	
	logInfo "Lock file: $fileToLock for project: $project and release: $release"
		
	# Get the git user name
	user=$(git config user.name)
	expectSuccess "Could not find the git username? Set one up first with: git config --global user.name 'John Doe'" $?
	
	# Build the file path of the given file including the subdirectory starting from git root
	relativeFilepath=$(discoverRelativeFilepathFromGitRoot "$fileToLock")
	expectSuccess "Error while discovering the relative filepath from git root occurred: $relativeFilepath" $?
	
	# Get the hash of the file content
	fileContentHash=$(git hash-object "$fileToLock")
	expectSuccess "Error while creating the file content hash occurred: $fileContentHash" $?
	
	# Send lock request to the server
	logInfo "Send lock request to the server"
	lockResult=$(executeOnServer lock "'$user'" "'$project'" "'$release'" "'$relativeFilepath'" "'$fileContentHash'")
	expectSuccess "Server wasn't able to lock the file: $lockResult" $?
	
	# Make file writable
	logInfo "Make file writable: $fileToLock"
	chmod ugo+w "$fileToLock"
	
}

# Unlocks a previously locked file.
# Now other users can lock the file again, but only if they updated to the last unlocked version of the file.
#
# @param FILE File to unlock
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientUnlock() {
	checkParameter 1 "unlock [FILE]" "$@"
	local fileToUnlock="$1"
	logInfo "Unlock file: $fileToUnlock"
	
	# Check if the file exists
	expectFileExists "$fileToUnlock" "File $fileToUnlock can't be found"
	
	# Get the required properties
	needPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
		
	# Get the git user name
	user=$(git config user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	# Build the file path of the given file including the subdirectory starting from git root
	relativeFilepath=$(discoverRelativeFilepathFromGitRoot "$fileToUnlock")
	expectSuccess "Error while discovering the relative filepath from git root occurred: $relativeFilepath" $?
	
	# Get the hash of the file content
	fileContentHash=$(git hash-object "$fileToUnlock")
	expectSuccess "Error while creating the file content hash occurred: $fileContentHash" $?
	
	# Send unlock request to the server
	logInfo "Send unlock request to the server"
	unlockResult=$(executeOnServer unlock "'$user'" "'$project'" "'$release'" "'$relativeFilepath'" "'$fileContentHash'")
	expectSuccess "Server wasn't able to unlock the file: $unlockResult" $?
	
	# Set the file to readonly
	logInfo "Set file to readonly: $fileToUnlock"
	chmod ugo-w "$fileToUnlock"
}

# Cancel/release a lock.
# Releases the lock on the lock-server, so that other user can request locks for this file again.
# 
# @param FILE File for which the lock needs to be canceled
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientCancel() {
	checkParameter 1 "cancel [FILE]" "$@"
	local fileToCancel="$1"
	logInfo "Cancel lock of file: $fileToCancel"
	
	# Check if the file exists
	expectFileExists "$fileToCancel" "File $fileToCancel can't be found"
	
	# Get the required properties
	needPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
	
	# Build the file path of the given file including the subdirectory starting from git root
	relativeFilepath=$(discoverRelativeFilepathFromGitRoot "$fileToCancel")
	expectSuccess "Error while discovering the relative filepath from git root occurred: $relativeFilepath" $?
	
	# Get the hash of the file content
	fileContentHash=$(git hash-object "$fileToCancel")
	expectSuccess "Error while creating the file content hash occurred: $fileContentHash" $?
	
	# Send cancel request to the server
	logInfo "Send cancel request to the server"
	cancelResult=$(executeOnServer cancel "'$project'" "'$release'" "'$relativeFilepath'" "'$fileContentHash'")
	expectSuccess "Server wasn't able to cancel the lock: $cancelResult" $?
	
	# Set the file to readonly
	logInfo "Set file to readonly: $fileToCancel"
	chmod ugo-w "$fileToCancel"
}

# Copies the hooks into the .git directory.
#
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientInitHooks() {
	discoverGitConfig gitConfig
	logDebug "Copy hooks to: ${gitConfig}hooks"
	cp "${LOCK_CLIENT_BIN_DIR}/pre-receive" "${gitConfig}hooks"
	chmod u+x "${gitConfig}hooks/pre-receive"
}

# Shows the current project, release and the locks of the user.
#
# @return_codes 0=success 1=failure
# @return_value Project, release and list of file locks
lockClientStatus() {
	checkParameter 0 "lockClientStatus()" "$@"
	
	# Log Project and Release
	needPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
	
	# Get the git user name
	user=$(git config user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	logDebug "Request user locks from server"
	result=$(executeOnServer show-user-locks "'$user'")
	expectSuccess "Server wasn't able get the user locks: $result" $?
	
	echo "Project: $project"
	echo "Release: $release"
	echo "-- Locked files:"
	echo "$result"
}

# Shows locks of all users
#
# @return_codes 0=success 1=failure
# @return_value List of all locked files
lockClientShowAllLocks() {
	checkParameter 0 "lockClientShowAllLocks()" "$@"
	logDebug "Request all locks from server"
	result=$(executeOnServer all-locks)
	expectSuccess "Server wasn't able get all locks: $result" $?
	echo "$result"
}

# Switches the project/release and create those on the server if not already exists.
#
# @param PROJECT Project to switch to
# @param RELEASE Release to switch to
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientSwitchProject() {
	checkParameter 2 "lockClientSwitchProject() [PROJECT] [RELEASE]" "$@"
	local project="$1"; local release="$2"
	
	# Get the git user name
	user=$(git config user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	# Check if user has locks
	result=$(executeOnServer show-user-locks "'$user'")
	expectSuccess "Server wasn't able get the user locks: $result" $?
	if [ "$result" != "User has no locks" ]; then
		expectSuccess "User still has locks, unable to switch the project. Remove all locks first." 1
	fi
	
	lockClientSetProperty "-p" "$project"
	lockClientSetProperty "-r" "$release"
	
	# Init server to create the new project and release if not already exists
	lockClientCreateProject
	expectSuccess "Server wasn't able to init the project $returnValue" $?
}

# Sends the given command to the lock-server via ssh.
#
# The used command can be overridden with the environment variable LOCK_SERVER_SSH_COMMAND.
# If this variable is set, it will be used as the prefix of the send command.
# Used for unit-testing to directly send the command to the lock-server script without involving ssh.
# 
# @return_codes Return code from the server
# @return_value Return value from the server
executeOnServer() {
	# Get property file
	needPropertyFilePath propertyFile
	
	# Build ssh command
	if [ -z "$LOCK_SERVER_SSH_COMMAND" ]; then
		needProperty remoteUser "$propertyFile" "$REMOTE_USER_PROPERTY_KEY"
		needProperty serverAddress "$propertyFile" "$SERVER_ADDRESS_PROPERTY_KEY"
		needProperty sshPort "$propertyFile" "$SSH_PORT_PROPERTY_KEY"
		sshCommand="ssh"
		
		# Check if a ssh port and remote user was given
		if [ -n "$sshPort" ]; then sshCommand="$sshCommand -p $sshPort "; fi
		if [ -n "$remoteUser" ]; then sshCommand="$sshCommand ${remoteUser}@"; fi
		
		sshCommand="${sshCommand}${serverAddress} \$LOCK_SERVER_BIN_DIR/lock-server.sh"
	else
		sshCommand="$LOCK_SERVER_SSH_COMMAND"
	fi

	# Check if debug logging is requested
	if [ "$logLevel" != "" ] && [ "$logLevel" -ge "$LOG_LEVEL_DEBUG" ]; then
		sshCommand="${sshCommand} --debug"
	else
		sshCommand="${sshCommand} --quiet"
	fi
	
	# Execute the command on the server and redirect stderr directly to tty
	# to see the server log directly (the 'normal' remote function return value goes to stdout)
	logDebug "[Connector] Send request to server: $@"
	logDebug "[Connector] Send command to server: $sshCommand $@"
	if [ -n "$ttyDevice" ]; then
		returnValue=$($sshCommand "$@" 2> "$ttyDevice")
	else
		returnValue=$($sshCommand "$@" 2>> "git-lock-server.log")
	fi
	local returnCode=$?
	logDebug "[Connector] Return code from server: $returnCode"
	logDebug "[Connector] Return value from server: $returnValue"
		
	echo "$returnValue"
	return $returnCode
}

# Checks if server properties are missing in the git-lock properties file.
# If properties are missing, it will ask the user to enter the missing values.
#
# The method how the user will be asked has to provided by the parent script with the function askForInput.
# This is used for the unit-tests to provide a headless execution. 
#
# @return_codes 0=success 1=failure
# @return_value nothing
askForAllMissingServerProperties() {
	# Check if property file exists
	getPropertyFilePath propertyFile $PROPERTY_FILE
	if [ ! -e "$propertyFile" ]; then
		logInfo "Create git-lock property file: $propertyFile"
		returnValue=$(touch "$propertyFile")
		expectSuccess "Property file can't be created: $returnValue" $?
	fi
	
	# Ask the user for all missing server properties
	for requiredProperty in "${REQUIRED_SERVER_PROPERTIES[@]}"; do
		local propertyKey=$(echo "$requiredProperty" | cut -f1 -d':')
		readProperty propertyValue "$propertyFile" "$propertyKey"
		if [ $? -ne 0 ]; then
			local question=$(echo "$requiredProperty" | cut -f2 -d':')
			local input=$(askForInput "${question}: ")
			writeProperty "$propertyFile" "$propertyKey" "$input"
		fi
	done
}

# Checks if properties are missing in the git-lock properties file.
# If properties are missing, it will ask the user to enter the missing values. 
#
# @return_codes 0=success 1=failure
# @return_value nothing
askForAllMissingProperties() {
	askForAllMissingServerProperties "$@"
	
	# Show all available projects on server
	logInfo "------------------------------"
	logInfo "Lookup existing projects on lock-server"
	returnValue=$(lockClientLookupServer "projects")
	if [ $? -ne 0 ]; then
		logInfo "There are no projects available on the lock-server so far"
	else
		logInfo "Existing projects:"
		logInfo "$returnValue"
	fi
	logInfo "------------------------------"
	
	# Ask the user for all missing client properties
	for requiredProperty in "${REQUIRED_PROPERTIES[@]}"; do
		local propertyKey=$(echo "$requiredProperty" | cut -f1 -d':')
		readProperty propertyValue "$propertyFile" "$propertyKey"
	  
		if [ $? -ne 0 ]; then
			local question=$(echo "$requiredProperty" | cut -f2 -d':')
			local input=$(askForInput "${question}: ")
			writeProperty "$propertyFile" "$propertyKey" "$input"
		fi
	done
}
