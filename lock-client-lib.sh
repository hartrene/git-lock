#!/bin/bash

# Copyright 2013 Rene Hartmann
# 
# This file is part of git-lock.
# 
# git-lock is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# git-lock is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with git-lock.  If not, see <http://www.gnu.org/licenses/>.
# 
# Additional permission under GNU GPL version 3 section 7:
# 
# If you modify the Program, or any covered work, by linking or
# combining it with the OpenSSL project's OpenSSL library (or a
# modified version of that library), containing parts covered by the
# terms of the OpenSSL or SSLeay licenses, the licensors of the Program
# grant you additional permission to convey the resulting work.
# Corresponding Source for a non-source form of such a combination
# shall include the source code for the parts of OpenSSL used as well
# as that of the covered work.

# git-lock functions
#
# Available git-lock commands:
#
# init
#	Initializes git-lock
# init-project
#	Initializes the project and release on the lock-server
# add [FILE]
#	Adds a file to be lockable
# lock [FILE]
#	Locks a file on the lock-server, so that no other user can edit this file until the lock is released (unlock).
# unlock [FILE]
#	Unlocks a previously locked file
# cancel [FILE]
#	Cancel/release a lock
# remove [FILE]
#	Removes a file to be lockable
#
# Lock-server commands:
# 
# lookup-server-pubkey
#	Requests the lock-servers public key
# lookup-projects
#	Logs all existing projects and releases on the lock-server
# lookup-project [PROJECT]
# 	Lookup of the project directory on the lock-server
# lookup-release [PROJECT] [RELEASE]
#	Lookup of the release directory on the lock-server
#
# Configuration commands:
#
# context
#	Logs all git-lock properties
# set-property
#	Sets/Overrides the given git-lock properties
#		-project [PROJECT_NAME] 
#   	-release [RELEASE_NAME] 
#   	-remote-user [REMOTE_USER] 
#   	-server [SERVER_ADDRESS] 
#   	-ssh-port [SSH_PORT]
# switch-project [PROJECT_NAME]
#	Changes the project of that branch
# switch-release [RELEASE_NAME]
#	Changes the release of that branch
# switch-remote-user [REMOTE_USER]
#	Changes the lock-server username
# switch-server [SERVER_ADDRESS]
# 	Changes the address of the lock-server
# switch-ssh-port [SERVER_SSH_PORT]
#	Changes the ssh port of the lock-server

# Import util functions
. "${LOCK_CLIENT_BIN_DIR}lock-util.sh"

# Property file name which holds informatin of the current project/release and detials of the server connectivity
PROPERTY_FILE=".git-lock.properties"

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

# Main function which dispatches calls to all lock-client functions
# This function gets called from the shell script git-lock or it gets called directly from the unit-tests.
lockClient() {
	command="$1"
	
	# Shift the input variables so that the next function won't get the command ($2 becomes $1...)
	shift
	
	# Dispatch the incomming command to the correct function
	case "$command" in
		init) lockClientInit "$@";;
		init-project) lockClientInitServer "$@";;
		add) lockClientAdd "$@";;
		lock) lockClientLock "$@";;
		unlock) lockClientUnlock "$@";;
		cancel) lockClientCancel "$@";;
		remove) lockClientRemove "$@";;
		
		# Commands for property manipulation
		context) lockClientContext "$@";;
		set-property) lockClientSetProperty "$@";;
		switch-project) lockClientSetProperty -p "$@";;
		switch-release) lockClientSetProperty -r "$@";;
		switch-remote-user) lockClientSetProperty -ru "$@";;
		switch-server) lockClientSetProperty -server "$@";;
		switch-ssh-port) lockClientSetProperty -ssh-port "$@";;
		
		# Commands for questioning the server
		lookup-server-pubkey) lockClientLookupServerPubkey "$@";;
		lookup-projects) lockClientLookupServer "projects" "$@";;
		lookup-project) lockClientLookupServer "project" "$@";;
		lookup-release) lockClientLookupServer "release" "$@";;
		
		*)
			echo "git-lock unknown command: $command"
			exit 1;;
	esac
}

# Lookup of lock-server details
# lookup-project [PROJECT]: Lookup of the project directory on the lock-server
# lookup-release [PROJECT] [RELEASE]: Lookup of the release directory on the lock-server
# lookup-projects: Logs all existing projects and releases on the lock-server
#
# @return_codes 0=success 1=failure
# @return_value Project or release directory
lockClientLookupServer() {
	local lookupProperty="${1:-}"
	checkParameter 1 "lockClientLookupServer() [CMD]" "$lookupProperty"
	
	shift
	case "$lookupProperty" in
		project)
			checkParameter 1 "lookup-project [PROJECT]" "$@"
			returnValue=$(executeOnServer lookup-project-dir "'$1'");;
		release)
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

# Returns all git-lock properties
#
# @return_codes 0=success 1=failure
# @return_value git-lock properties
lockClientContext() {
	checkParameter 0 "context" "$@"
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	
	local contextData="$(cat "$propertyFile")"
	echo "$contextData"
}

# Sets/Overrides git-lock properties
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
	lockClientGetPropertyFilePath propertyFile
		
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
		
		if [ -z "$propertyValue" ]; then
			echo "No value given for switch$propertyId"
			exit 1
		fi
		
		case "$propertyId" in
			-p | -project) propertyKey="$PROJECT_PROPERTY_KEY";;
			-r | -release) propertyKey="$RELEASE_PROPERTY_KEY";;
			-ru | -remote-user) propertyKey="$REMOTE_USER_PROPERTY_KEY";;
			-s | -server) propertyKey="$SERVER_ADDRESS_PROPERTY_KEY";;
			-sp | -ssh-port) propertyKey="$SSH_PORT_PROPERTY_KEY";;
			*)
				echo "Error unknown property: $propertyId"
				exit 1;;
		esac
		
		writeProperty "$propertyFile" "$propertyKey" "$propertyValue"
		logInfo "Property $propertyKey was set to: $propertyValue"
		
		# Shift to the next pair of properties
		shift 2
	done
}

# Requests the lock-servers public key
#
# @param FILE File path in which the public key will be stored
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientLookupServerPubkey() {
	checkParameter 1 "lookup-server-pubkey [FILE]" "$@"
	local fileToStore="$1"
	
	# Send request to the server
	pubkey=$(executeOnServer pubkey)
	expectSuccess "Error while requesting the server public key occurred: $pubkey" $?
	
	# Save the pubkey
	echo "$pubkey" > "${fileToStore}"
}

# Initializes git-lock
# Creates the project and release on the lock-server
# Possibile to give the required properties as arguments: 
#   -project [PROJECT_NAME] 
#   -release [RELEASE_NAME] 
#   -remote-user [REMOTE_USER] 
#   -server [SERVER_ADDRESS] 
#   -ssh-port [SSH_PORT]
# If some properties were not given as arguments, it will ask to enter the missing properties
#
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientInit() {
	checkParameter 0 "init" "$@"
	logInfo "Init git-lock"
	
	# Get git-root
	discoverGitRoot gitRoot
	logDebug "Found git root in: $gitRoot"
	
	# Store the parameter if some where given
	lockClientSetProperty "$@"
	
	# Ask for all missing properties
	askForAllMissingProperties
	
	# Run the server init
	lockClientInitServer
	
	logInfo "git-lock init done"
}

# Initializes the project and release on the lock-server
#
# @return_codes 0=success 1=failure
# @return_value return value from the server
lockClientInitServer() {
	# Store the parameter if some where given
	lockClientSetProperty "$@"
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
		
	# Run the server init
	logDebug "Init project and release on server"
	returnValue=$(executeOnServer init "'$project'" "'$release'")
	expectSuccess "Server wasn't able to init the project $returnValue" $?
}

# Adds a file to be lockable
# Also is used to add a previously removed/banned file.
# The file will be readonly if the add was successful.
#
# @param FILE File to add
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientAdd() {
	checkParameter 1 "add [FILE]" "$@"
	local fileToAdd="$1"
	
	logInfo "Add file: $fileToAdd"
	
	# Check if the file exists
	expectFileExists "$fileToAdd" "File to add can't be found: $fileToAdd"
	
	# Check if init was running
	lockClientNeedPropertyFilePath propertyFile
	
	# Get the git user name
	user=$(git config --global user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileToAdd")
	expectSuccess "Error while creating the file name hash occurred: $fileNameHash" $?
	
	# Get the hash of the file content
	fileContentHash=$(git hash-object "$fileToAdd")
	expectSuccess "Error while creating the file content hash occurred: $fileContentHash" $?
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
	
	# Check if file was removed previously, in that case we have to remove the ban on the server
	local banConfirmationSignatureFile=".${fileToAdd}.lock-remove-confirm"
	local banConfirmationSignature=""
	if [ -e "$banConfirmationSignatureFile" ]; then
		banConfirmationSignature=$(cat "$banConfirmationSignatureFile")
	else 
		# Check if the file is already added
		ls ".${fileToAdd}.lock"* &> /dev/null
		if [ $? -eq 0 ]; then
			echo "File already added"
			exit 1
		fi
	fi
	
	# Send add request to the server
	logInfo "Send add request to the server"
	changeConfirmationSignature=$(executeOnServer add "'$user'" "'$project'" "'$release'" "$fileNameHash" "$fileContentHash" "$banConfirmationSignature")
	expectSuccess "Server wasn't able to add the file: $changeConfirmationSignature" $?
	
	# Save the change confirmation signature
	logInfo "File successfully added to the server"
	local changeConfirmationSignatureFile=".${fileToAdd}.lock-change-confirm"
	logDebug "Save change confirmation signature: $changeConfirmationSignature to: $changeConfirmationSignatureFile"
	echo "$changeConfirmationSignature" > "$changeConfirmationSignatureFile"
	
	# Set the file to readonly
	logInfo "Set file to readonly: $fileToAdd"
	chmod ugo-w "$fileToAdd"
	
	# If the file was banned before, remove the ban on the client side
	if [ -e "$banConfirmationSignatureFile" ]; then
		rm "$banConfirmationSignatureFile"
	fi
}

# Locks a file on the lock-server, so that no other user can edit this file until the lock is released (unlock).
# It is supported to directly lock a never added file.
# It stores the lock confirmation signature (lcs) from the lock-server, so that only this client who has the lcs can release the lock (unlock).
# It will make the file writable, if it was readonly before.
#
# It stores the project and release for which the lock was requested, so that it doesn't need to be given again on unlock or cancel.
# This makes it possible (not recommended), to switch the project or release after the file was locked and unlock the file later.
#
# @param FILE File to lock
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientLock() {
	checkParameter 1 "lock [FILE]" "$@"
	local fileToLock="$1"
	
	logInfo "Lock file: $fileToLock"
	
	# Check if the file exists
	expectFileExists "$fileToLock" "File to lock file can't be found: $fileToLock"
	
	# Check if the file was added before
	ls ".${fileToLock}.lock"* &> /dev/null
	if [ ! $? -eq 0 ]; then
		lockClientAdd "$fileToLock"
	fi
	
	# Check that the file is not already locked
	local lockSignatureFile=".${fileToLock}.lock"
	if [ -e "$lockSignatureFile" ]; then
		echo "File is already locked"
		exit 1
	fi
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
		
	# Get the git user name
	user=$(git config --global user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileToLock")
	expectSuccess "Error while creating the file name hash occurred: $fileNameHash" $?
	
	# Send lock request to the server
	logInfo "Send lock request to the server"
	
	# Check if the file was changed before
	local lastChangeConfirmationSignatureFile=".${fileToLock}.lock-change-confirm"
	if [ -e "$lastChangeConfirmationSignatureFile" ]; then
		# File was changed before, send last change confirmation signature
		lastChangeConfirmationSignature=$(cat "$lastChangeConfirmationSignatureFile")
		lockSignature=$(executeOnServer lock "'$user'" "'$project'" "'$release'" "$fileNameHash" "$lastChangeConfirmationSignature")
	else 
		# File was never locked before, don't send any change confirmation signature
		lockSignature=$(executeOnServer lock "'$user'" "'$project'" "'$release'" "$fileNameHash")
	fi 
	
	# Check if server execution was successful
	expectSuccess "Server wasn't able to lock the file: $lockSignature" $?
	
	# Save the lock signature
	logInfo "File successfully locked on server"
	logDebug "Save lock signature: $lockSignature to $lockSignatureFile"
	echo "$lockSignature" > "$lockSignatureFile"
	
	# Save the project and release for which the file was locked
	# If the user decides to switch the project before unlocking, we're not lost
	logDebug "Save project and release for which this lock was done"
	local lockDetailsFile=".${fileToLock}.lock-details"
	touch "$lockDetailsFile"
	writeProperty "$lockDetailsFile" "$PROJECT_PROPERTY_KEY" "$project"
	writeProperty "$lockDetailsFile" "$RELEASE_PROPERTY_KEY" "$release"
	
	# Make the file writable
	logInfo "Make file writable: $fileToLock"
	chmod u+w "$fileToLock"
}

# Unlocks a previously locked file 
# Now other users can lock the file again, but only if they updated to the last unlocked version of the file.
# It stores the unlock-confirmation-signature (ucs), with which new locks of this file can be requested.
# After unlocking the file will be readonly again. 
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
	
	# Check if lock signature can be found
	local lockSignatureFile=".${fileToUnlock}.lock"
	expectFileExists "$lockSignatureFile" "File is not locked."
	
	# Check if the lock details file can be found
	local lockDetailsFile=".${fileToUnlock}.lock-details"
	expectFileExists "$lockDetailsFile" "Lock details file couldn't be found."
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	needProperty project "$lockDetailsFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$lockDetailsFile" "$RELEASE_PROPERTY_KEY"
		
	# Get the git user name
	user=$(git config --global user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileToUnlock")
	expectSuccess "Error while creating the file name hash occurred: $fileNameHash" $?
	
	# Get the hash of the file content
	fileContentHash=$(git hash-object "$fileToUnlock")
	expectSuccess "Error while creating the file content hash occurred: $fileContentHash" $?
	
	# Get the lock signature
	local lockSignature=$(cat "$lockSignatureFile")
	
	# Send unlock request to the server
	logInfo "Send unlock request to the server"
	changeConfirmationSignature=$(executeOnServer unlock "'$user'" "'$project'" "'$release'" "$fileNameHash" "$fileContentHash" "$lockSignature")
	expectSuccess "Server wasn't able to unlock the file: $changeConfirmationSignature" $?
	
	# Save the change confirmation signature
	logInfo "File successfully unlocked on server"
	local changeConfirmationSignatureFile=".${fileToUnlock}.lock-change-confirm"
	logDebug "Save change confirmation signature: $changeConfirmationSignature to: $changeConfirmationSignatureFile"
	echo "$changeConfirmationSignature" > "$changeConfirmationSignatureFile"
	
	# Cleanup the filesystem
	rm "$lockSignatureFile"
	rm "$lockDetailsFile"
	
	# Set the file to readonly
	logInfo "Set file to readonly: $fileToUnlock"
	chmod ugo-w "$fileToUnlock"
}

# Cancel/release a lock
# Releases the lock on the lock-server, so that other user can request locks for this file again.
# 
# No new change-confirmation-signature will be created.
# 
# 
# @param FILE File for which the lock needs to be canceled
# @return_codes 0=success 1=failure
# @return_value
lockClientCancel() {
	checkParameter 1 "cancel [FILE]" "$@"
	local fileToCancel="$1"
	
	logInfo "Cancel lock of file: $fileToCancel"
	
	# Check if the file exists
	expectFileExists "$fileToCancel" "File $fileToCancel can't be found"
	
	# Check if lock signature can be found
	local lockSignatureFile=".${fileToCancel}.lock"
	expectFileExists "$lockSignatureFile" "File is not locked."
	
	# Check if the lock details file can be found
	local lockDetailsFile=".${fileToCancel}.lock-details"
	expectFileExists "$lockDetailsFile" "Lock details file couldn't be found."
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	needProperty project "$lockDetailsFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$lockDetailsFile" "$RELEASE_PROPERTY_KEY"
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileToCancel")
	expectSuccess "Error while creating the file name hash occurred: $fileNameHash" $?
	
	# Get the lock signature
	local lockSignature=$(cat "$lockSignatureFile")
	
	# Send cancel request to the server
	logInfo "Send cancel request to the server"
	cancelReturnValue=$(executeOnServer cancel "'$project'" "'$release'" "$fileNameHash" "$lockSignature")
	expectSuccess "Server wasn't able to cancel the lock: $cancelReturnValue" $?
	
	# Delete the unlock files
	rm "$lockSignatureFile"
	rm "$lockDetailsFile"
	
	# Set the file to readonly
	logInfo "Set file to readonly: $fileToCancel"
	chmod ugo-w "$fileToCancel"
}

# Removes a file to be lockable
# This file will be banned on the lock-server, so that no more locks for this file will be accepted.
# If the file needs to be locked again, just use git-lock add [FILE]
# 
# @param FILE File for which no lock requests should be allowed anymore
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientRemove() {
	checkParameter 1 "remove [FILE]" "$@"
	local fileToRemove="$1"
	
	logInfo "Remove file: $fileToRemove"
	
	# Check if file was already removed
	local banConfirmationSignatureFile=".${fileToRemove}.lock-remove-confirm"
	if [ -e "$banConfirmationSignatureFile" ]; then
		echo "File already removed"
		exit 1
	fi
	
	# Check if the file exists
	expectFileExists "$fileToRemove" "File to remove file can't be found: $fileToRemove"
	
	# Check if the file was locked before
	ls ".${fileToRemove}.lock"* &> /dev/null
	if [ ! $? -eq 0 ]; then
		echo "Can only remove files which were added (git-lock add) or locked (git-lock lock) before."
		exit 1
	fi
	
	# Get the required properties
	lockClientNeedPropertyFilePath propertyFile
	needProperty project "$propertyFile" "$PROJECT_PROPERTY_KEY"
	needProperty release "$propertyFile" "$RELEASE_PROPERTY_KEY"
		
	# Get the git user name
	user=$(git config --global user.name)
	expectSuccess "Could not find the git username? $user" $?
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileToRemove")
	expectSuccess "Error while creating the file name hash occurred: $fileNameHash" $?
	
	# Get the hash of the file content
	fileContentHash=$(git hash-object "$fileToRemove")
	expectSuccess "Error while creating the file content hash occurred: $fileContentHash" $?
	
	# Send ban request to the server
	logInfo "Send ban request to the server"
	
	# Check if the file was changed before
	local lastChangeConfirmationSignatureFile=".${fileToRemove}.lock-change-confirm"
	if [ -e "$lastChangeConfirmationSignatureFile" ]; then
		# File was changed before, send last change confirmation signature
		lastChangeConfirmationSignature=$(cat "$lastChangeConfirmationSignatureFile")
		banConfirmationSignature=$(executeOnServer ban "'$user'" "'$project'" "'$release'" "$fileNameHash" "$fileContentHash" "$lastChangeConfirmationSignature")
	else 
		# File was never changed before, don't send any change confirmation signature
		banConfirmationSignature=$(executeOnServer ban "'$user'" "'$project'" "'$release'" "$fileNameHash" "$fileContentHash")
	fi 
	
	# Check if server execution was successful
	expectSuccess "Server wasn't able to ban the file: $banConfirmationSignature" $?
	
	# Save the ban confirmation signature
	logInfo "File successfully banned on server"
	logDebug "Save ban confirmation signature: $banConfirmationSignature to $banConfirmationSignatureFile"
	echo "$banConfirmationSignature" > "$banConfirmationSignatureFile"
	
	# Cleanup the filesystem
	if [ -e "$lastChangeConfirmationSignatureFile" ]; then
		rm "$lastChangeConfirmationSignatureFile"
	fi
	
	logInfo "File successfully banned on lock server"
}


# Creates the filepath of the git-lock property file
#
# @param RESULT_VARIABLE variable in which the path will be stored
# @return_codes 0=success 1=failure
# @return_value nothing
lockClientGetPropertyFilePath() {
	checkParameter 1 "lockClientGetPropertyFilePath() [RESULT_VARIABLE]" "$@"
	local resultVariable=$1; eval $resultVariable=
	
	discoverGitRoot gitRoot
	
	eval $resultVariable="'${gitRoot}${PROPERTY_FILE}'"
}

# Create the git-lock properties file path and checks if it exists
#
# @param RESULT_VARIABLE variable in which the path will be stored
# @return_codes 0=file exists 1=file does not exist
# @return_value nothing
lockClientNeedPropertyFilePath() {
	checkParameter 1 "lockClientNeedPropertyFilePath() [RESULT_VARIABLE]" "$@"
	local resultVariable=$1; eval $resultVariable=

	lockClientGetPropertyFilePath propertyFilePath
		
	if [ ! -e "$propertyFilePath" ]; then
		local errorMsg="Git-lock property file '$propertyFilePath' not found. Run 'git-lock init' first."
		logError "$errorMsg"
		echo "$errorMsg"
		exit 1
	fi
	
	eval $resultVariable="'${propertyFilePath}'"
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
	lockClientNeedPropertyFilePath propertyFile
	
	# Build ssh command
	if [ -z "$LOCK_SERVER_SSH_COMMAND" ]; then
		needProperty remoteUser "$propertyFile" "$REMOTE_USER_PROPERTY_KEY"
		needProperty serverAddress "$propertyFile" "$SERVER_ADDRESS_PROPERTY_KEY"
		needProperty sshPort "$propertyFile" "$SSH_PORT_PROPERTY_KEY"
		sshCommand="ssh "
		
		# Check if a ssh port and remote user was given
		if [ -n "$sshPort" ]; then sshCommand="$sshCommand -p $sshPort "; fi
		if [ -n "$remoteUser" ]; then sshCommand="$sshCommand ${remoteUser}@"; fi
		
		sshCommand="$sshCommand${serverAddress} \$LOCK_SERVER_BIN_DIR/lock-server.sh"
	else
		sshCommand="$LOCK_SERVER_SSH_COMMAND"
	fi

	# Check if debug logging is requested
	if [ $logLevel -ge $LOG_LEVEL_DEBUG ]; then
		sshCommand="${sshCommand} --debug"
	fi
	
	# Execute the command on the server and redirect stderr directly to tty
	# to see the server log directly (the 'normal' remote function return value goes to stdout)
	logDebug "[Connector] Send request to server: $@"
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

# Checks if properties are missing in the git-lock properties file.
# If properties are missing, it will ask the user to enter the missing values.
#
# The method how the user will be asked has to provided by the parent script with the function askForInput.
# This is used for the unit-tests to provide a headless execution. 
#
# @return_codes 0=success 1=failure
# @return_value nothing
askForAllMissingProperties() {
	# Check if property file exists
	lockClientGetPropertyFilePath propertyFile
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
	
	# Ask the user for all missing properties
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