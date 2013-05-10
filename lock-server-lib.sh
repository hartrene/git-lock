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


# lock-server functions
#
# This script needs the following environment parameter:
#   LOCK_SERVER_BIN_DIR  Directory which contains all lock-server scripts
#   LOCK_SERVER_DIR      Working directory of this lock-server to hold the project/release folders and the lock files
#
# Available lock-server commands:
# 
# init [PROJECT_NAME] [RELEASE_NAME]
# 	Initializes a new project and release on the server
# pubkey
#	Returns the servers public-key to be able to verify the signatures of the lock-server
# add [USER] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH]
#	Adds a new/banned file to the lock-server
# lock [USER] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE]
#	Locks a file
# unlock [USER_NAME] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH] [LOCK_CONFIRMATION_SIGNATURE]
#	Unlocks a file
# cancel [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [LOCK_CONFIRMATION_SIGNATURE]
#	Cancel of a lock, in case the lock change needs to be dropped
# ban [USER_NAME] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH] [PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE]
#	Bans a file on the lock server. No more locking will be allowed for this file.
# lookup-projects
#	Logs all existing projects and releases
# lookup-project-dir
#	Returns the directory of the given project
# lookup-release-dir
#	Returns the directory of the given release

# Import util functions
. "${LOCK_SERVER_BIN_DIR}lock-util.sh"

LOCK_SERVER_CMD_NAME="lockServer"
LOCK_SERVER_LOG="${LOCK_SERVER_DIR}/lock-server.log"
LOCK_SERVER_KEYS_DIR="${LOCK_SERVER_DIR}/.keys"
LOCK_SERVER_PRIVATE_KEY_FILE="${LOCK_SERVER_KEYS_DIR}/.private_key"
LOCK_SERVER_PUBLIC_KEY_FILE="${LOCK_SERVER_KEYS_DIR}/.public_key"
LOCK_SERVER_MUTEX_NAME="${LOCK_SERVER_DIR}/.mutex"
LOCK_SERVER_LOG_PREFIX="[Lock-Server] "

# Main function which dispatches calls to all lock-server functions
# This function gets called from lock-server.sh which gets called from a client via ssh or it gets called directly from the unit-tests.
#
# To avoid parallel execution errors of the lock-server functions, it will requests a mutex in the beginning to block all other requests.
# The mutex will be released in case of INT TERM EXIT of the script.
lockServer() {
	command="$1"
	
	# Check if the global working dir is set
	if [ -z "${LOCK_SERVER_DIR:-}" ]; then
		errorMsg="[Lock-Server] Environment variable LOCK_SERVER_DIR not found"
		logError "$errorMsg"
		echo "$errorMsg"
		exit 1
	fi
	
	# Check if no other script is running at the moment
	returnValue=$(acquireMutex "$LOCK_SERVER_MUTEX_NAME" 1 20)
	expectSuccess "Another script is already running, please try again later $returnValue" $?
	# Make sure that the mutex gets removed if the program exits abnormally or get killed
	trap "releaseMutex $LOCK_SERVER_MUTEX_NAME; exit" INT TERM EXIT
	
	# Shift the input variables so that the next function won't get the command ($2 becomes $1...)
	shift
	
	# Dispatch the incomming command to the correct function
	case "$command" in
		init) lockServerInit "$@";;
		pubkey) lockServerPubkey "$@";;
		add) lockServerAdd "$@";;
		lock) lockServerLock "$@";;
		unlock) lockServerUnlock "$@";;
		cancel) lockServerCancel "$@";;
		ban) lockServerBan "$@";;
		lookup-projects) lockServerLookupProjects "$@";;
		
		# Shortcut commands
		lookup-project-dir) 
			checkParameter 1 "lookup-project-dir [PROJECT_NAME]" "$@"
			checkAndReturnDir "${LOCK_SERVER_DIR}/$1";;
		lookup-release-dir)
			checkParameter 2 "lookup-release-dir [PROJECT_NAME] [RELEASE_NAME]" "$@"
			checkAndReturnDir "${LOCK_SERVER_DIR}/$1/$2";;
			
		*)
			logError "Error executing command on lock server: Unknown command: $command"
			exit 1;;
	esac
	
	# Save the return code of the last function, before cleaning up things
	commandReturnCode=$?
	
	# Cleanup before the program
	# Release the mutex so that other scripts are free to run
	returnValue=$(releaseMutex "$LOCK_SERVER_MUTEX_NAME")
	expectSuccess "Error while release the mutx occurred" $?
	
	return $commandReturnCode
}

# Initializes a new project and release on the server
# Projects and releases are represented as directories on the lock-server
#
# @param PROJECT_NAME Name of the new project
# @param RELEASE_NAME Name of the new release
# @return_codes 0=success 1=failure
# @return_value
lockServerInit() {
	checkParameter 2 "init [PROJECT_NAME] [RELEASE_NAME]" "$@"
	projectName="$1"; releaseName="$2";
	
	logInfo "Init project $projectName and release $releaseName"
	
	# Create server dir if not yet exists
	createDir "${LOCK_SERVER_KEYS_DIR}" "Created lock server working dir: ${LOCK_SERVER_KEYS_DIR}" "Unable to create the working dir: ${LOCK_SERVER_KEYS_DIR}"
	
	if [ $? = 0 ]; then
		logDebug "Create lock server key pairs"
		
		# Create private key for this server
		returnValue=$(openssl genrsa -out "$LOCK_SERVER_PRIVATE_KEY_FILE" 1024 2>>"$LOCK_SERVER_LOG")
		expectSuccess "openssl error while creating the private key occurred. For more details see the log file: LOCK_SERVER_LOG" $?
		
		# Create public key for this server
		returnValue=$(openssl rsa -in "$LOCK_SERVER_PRIVATE_KEY_FILE" -pubout > "$LOCK_SERVER_PUBLIC_KEY_FILE" 2>>"$LOCK_SERVER_LOG")
		expectSuccess "openssl error while creating the public key occurred. For more details see the log file: LOCK_SERVER_LOG" $?
	fi
	
	# Create project dir if not yet exists
	createDir "${LOCK_SERVER_DIR}/${projectName}" "Created new project directory on lock server: ${LOCK_SERVER_DIR}/${projectName}" "Unable to create the project directory: ${LOCK_SERVER_DIR}/${projectName}"
	
	# Create release dir if not yet exists
	createDir "${LOCK_SERVER_DIR}/${projectName}/${releaseName}" "Created new release directory: ${LOCK_SERVER_DIR}/${projectName}/${releaseName}" "Unable to create the release directory: ${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	
	return 0
}

# Returns the servers public-key to be able to verify the signatures of the lock-server
#
# @return_codes 0=success 1=failure
# @return_value public-key
lockServerPubkey() {
	checkParameter 0 "pubkey" "$@"
	echo "$(cat "$LOCK_SERVER_PUBLIC_KEY_FILE")"
}

# Logs all existing projects and releases
# Example-> Project: myProject [Releases: 0.1, 0.2, 0.5]
#
# @return_codes 0=success 1=failure
# @return_value nothing
lockServerLookupProjects() {

	# Check if init was running
	test -d "${LOCK_SERVER_DIR}"
	expectSuccess "Lock-server working directory ${LOCK_SERVER_DIR} is not ready yet, run init first" $?
	
	# Check if projects are available
	local projectDirectoryCount=$(find "${LOCK_SERVER_DIR}" -maxdepth 1 -type d -not -name ".*" | wc -l)
	if [ $projectDirectoryCount -le 1 ]; then
		logInfo "No project available on lock-server"
		return 1
	fi
	
	local projectCount=0
	for project in "${LOCK_SERVER_DIR}"/*; do
		if [ -f "$project" ]; then continue; fi
		
		if [ $projectCount -ne 0 ]; then
			echo ""
		fi
	
		echo -n "Project: "
		echo -n $(echo ${project/"${LOCK_SERVER_DIR}/"/})
		echo -n " [Releases: "
		
		local releaseCount=0
		for release in "${project}"/*; do
			if [ -f "$project" ]; then continue; fi
			
			# Check if projects are available
			local releaseDirectoryCount=$(find "${project}" -maxdepth 1 -type d -not -name ".*" | wc -l)
			if [ $releaseDirectoryCount -le 1 ]; then
				echo -n "none"
				continue
			fi
			
			if [ $releaseCount -ne 0 ]; then
				echo -n ", "
			fi
			
			echo -n $(echo ${release/"${project}/"/})
			
			releaseCount=$(($releaseCount+1))
		done
		
		echo -n "]"
		
		projectCount=$(($projectCount+1))
	done
}

# Adds a new file to the lock-server
#
# @param USER Name of the user who would like to add the file
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param FILE_CONTENT_HASH Hash of the current content of the file
# @return_codes 0=success 1=failure
# @return_value Change-confirmation-signature (ccs) for the received content of the file. Only who sends this ccs can lock this file.
lockServerAdd() {
	checkAtLeastParameter 5 "add [USER] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH] [LOCK_BAN_CONFIRMATION_SIGNATURE" "$@"
	user="$1"; projectName="$2"; releaseName="$3"; fileNameHash="$4"; fileContentHash="$5";
	banConfirmationSignature="${6:-}"
	
	logDebug "Add file: $fileNameHash"
	
	# Check if the file is banned
	lockBanFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lockban"
	if [ -e "$lockBanFilePath" ]; then
		# Check if the ban confirmation signature was send
		if [ -z "$banConfirmationSignature" ]; then
			errorMsg="File is banned but no ban confirmation signature was send."
			logError "$errorMsg"
			exit 1
		fi
		
		# Verify received ban confirmation signature against the content hash
		logDebug "File was banned before, check ban-configuration-signature"
		verifySignature "$LOCK_SERVER_PUBLIC_KEY_FILE" "$banConfirmationSignature" $(cat "$lockBanFilePath")
		expectSuccess "Error: Validation of the received ban confirmation signature failed. Get the latest version first." $?
		
		# Remove the ban
		logDebug "Remove ban to file"
		rm "$lockBanFilePath"
		rm "${lockBanFilePath}info"
	fi
	
	# Try to lock the file
	logDebug "Try to attain a temporarily lock for the added file, to check no one has a lock for the file at the moment"
	lockSignature=$(lockServerLock "$user" "$projectName" "$releaseName" "$fileNameHash")
	expectSuccess "Unable to add the file: $lockSignature" $?
	
	# Try to unlock the file
	logDebug "Release the temporarily lock for the added file and grab the change confirmation signature"
	changeConfirmationSignature=$(lockServerUnlock "$user" "$projectName" "$releaseName" "$fileNameHash" "$fileContentHash" "$lockSignature")
	expectSuccess "Unable to unlock the temporarily lock for the added file: $changeConfirmationSignature" $?
	
	echo "$changeConfirmationSignature"
}

# Locks a file
#
# @param USER Name of the user who would like to lock file
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE (optional) If the file was added/unlocked in the past it can only locked again, if the correct change-confirmation-signature is send
# @return_codes 0=success 1=failure
# @return_value lock-confirmation-signature (lcs). Only who sends this lcs can unlock/cancel this lock.
lockServerLock() {
	checkAtLeastParameter 4 "lock [USER] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE]" "$@"
	user="$1"; projectName="$2"; releaseName="$3"; fileNameHash="$4";
	previousChangeConfirmSignature="${5:-}"
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	lockInfoFilePath="${lockFilePath}info"
	lockBanFilePath="${lockFilePath}ban"
	lockBanInfoFilePath="${lockFilePath}baninfo"
	
	logDebug "Lock file: $fileNameHash"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if file is locked
	if [ -e "$lockFilePath" ]; then
		echo "File is locked by $(cat "${lockInfoFilePath}" | sed ':a;N;$!ba;s/\n/. /g')"
		exit 1
	fi
	
	# Check if the file was banned
	if [ -e "$lockBanFilePath" ]; then
		echo "File was banned by $(cat "${lockBanInfoFilePath}" | sed ':a;N;$!ba;s/\n/. /g')"
		exit 1
	fi
	
	# Check if this file was locked in the past and in that case check if the received change confirmation signature was the latest
	if [ -e "${lockFilePath}.latest" ]; then
		# Check if a change confirmation signature was send
		if [ -z "$previousChangeConfirmSignature" ]; then
			echo "File was already modified by $(cat "${lockFilePath}.latestinfo" | sed ':a;N;$!ba;s/\n/. /g'). Get the latest version first."
			exit 1
		fi
		
		# Check if the received change confirmation signature fits to that latest change
		logDebug "Check that the received change confirmation signature fits to the last known state of this file"
		verifySignature "$LOCK_SERVER_PUBLIC_KEY_FILE" "$previousChangeConfirmSignature" "$(cat "${lockFilePath}.latest")"; validationResult=$?
		expectSuccess "File was already modified by $(cat "${lockFilePath}.latestinfo" | sed ':a;N;$!ba;s/\n/. /g'). Get the latest version first." $validationResult
		
		# Store the last known content hash as the lock information
		echo "$(cat "${lockFilePath}.latest")-lock" > "$lockFilePath"
	else
		# This is the first lock to that file, so we store the first lock entry
		echo "${fileNameHash}-first-lock" > "$lockFilePath"
	fi
	
	# Create new lock entry for this file
	echo "user:$user" > "$lockInfoFilePath"
	echo "timestamp:$(date)" >> "$lockInfoFilePath"
	
	# Create the lock signature for the received content hash which will be send back to the client
	# Only the client who has this lock signature can unlock this file
	lockSignatureFile="${lockFilePath}.lsig"
	logDebug "Create lock signature for: $(cat "${lockFilePath}")"
	returnValue=$(openssl dgst -sha1 -sign "$LOCK_SERVER_PRIVATE_KEY_FILE" "$lockFilePath" > "${lockSignatureFile}" 2>>"$LOCK_SERVER_LOG")
	
	# Check if the signature creation failed, in that case remove the lock files and return the error msg
	if [ $? -ne 0 ]; then
		rm "$lockFilePath"
		rm "$lockInfoFilePath"
		echo "Openssl error while creating the lock signature. For more details see the log file: $LOCK_SERVER_LOG"
		exit 1
	fi
	
	# Encode the binary lock signature to base64 and remove all \n, so it can be easily transferred to the client
	lockConfirmationSignature=$(cat "${lockSignatureFile}" | base64 | sed ':a;N;$!ba;s/\n//g')
	logDebug "Created lock signature: $lockConfirmationSignature"
	
	# delete the temporarily created lock signature file
	rm "$lockSignatureFile"
	
	echo "$lockConfirmationSignature"
}

# Unlocks a file
#
# @param USER Name of the user who would like to unlock the file
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param FILE_CONTENT_HASH Hash of the current content of the file
# @param LOCK_CONFIRMATION_SIGNATURE Returned signature from the lock call
# @return_codes 0=success 1=failure
# @return_value change-confirmation-signature (ccs). Only who sends this ccs can lock this file again.
lockServerUnlock() {
	checkParameter 6 "unlock [USER_NAME] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH] [LOCK_CONFIRMATION_SIGNATURE]" "$@"
	user="$1"; projectName="$2"; releaseName="$3"; fileNameHash="$4"; fileContentHash="$5"; lockSignature="$6"
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	lockInfoFilePath="${lockFilePath}info"
	
	logDebug "Unlock file: $fileNameHash"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if file is locked
	if [ ! -e "$lockFilePath" ]; then
		echo "File is not locked"
		exit 1
	fi
	
	# Verify received lock signature
	expectFileExists "$lockFilePath" "File to unlock couldn't be found on the server. Check project/release/filename or file was never locked"
	verifySignature "$LOCK_SERVER_PUBLIC_KEY_FILE" "$lockSignature" "$(cat "$lockFilePath")"
	expectSuccess "Error: Validation of the received lock signature failed" $?
	
	# Delete lock files
	rm "$lockFilePath"
	rm "$lockInfoFilePath"
	
	# Save the received content hash, so that we are able to figure out the next time someone likes to lock this file, that he is not trying to modify an old version
	echo "$fileContentHash" > "${lockFilePath}.latest"
	
	# Save the details who did and when was the latest change
	latestChangeInfoFile="${lockFilePath}.latestinfo"
	echo "user:$user" > "$latestChangeInfoFile"
	echo "timestamp:$(date)" >> "$latestChangeInfoFile"
	
	# Create and return change confirmation signature for the new content
	logDebug "Create change confirmation signature for: $(cat "${lockFilePath}.latest")"
	changeConfirmationSignatureFile="${lockFilePath}.ccsig"
	returnValue=$(openssl dgst -sha1 -sign "$LOCK_SERVER_PRIVATE_KEY_FILE" "${lockFilePath}.latest" > "$changeConfirmationSignatureFile" 2>>"$LOCK_SERVER_LOG")
	expectSuccess "Openssl error while creating the change confirmation signature. For more details see the log file: $LOCK_SERVER_LOG" $?
	
	# Encode the binary change confirmation signature to base64 and remove all \n, so it can be easily transferred to the client
	changeConfirmationSignature=$(cat "$changeConfirmationSignatureFile" | base64 | sed ':a;N;$!ba;s/\n//g')
	logDebug "Created change confirmation signature: $changeConfirmationSignature"
	
	# delete the temporarily created change confirmation signature file
	rm "$changeConfirmationSignatureFile"
	
	echo "$changeConfirmationSignature"
}

# Cancel of a lock, in case the lock change needs to be dropped
#
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param LOCK_CONFIRMATION_SIGNATURE Returned signature from the lock call
# @return_codes 0=success 1=failure
# @return_value nothing
lockServerCancel() {
	checkParameter 4 "cancel [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [LOCK_CONFIRMATION_SIGNATURE]" "$@"
	projectName="$1"; releaseName="$2"; fileNameHash="$3"; lockSignature="$4"
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	lockInfoFilePath="${lockFilePath}info"
	
	logInfo "Cancel lock for file: $fileNameHash"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if file is locked
	if [ ! -e "$lockFilePath" ]; then
		echo "File is not locked"
		exit 1
	fi
	
	# Verify the received lock signature against the content hash
	verifySignature "$LOCK_SERVER_PUBLIC_KEY_FILE" "$lockSignature" $(cat "$lockFilePath")
	expectSuccess "Error: Validation of the received lock signature failed" $?
	
	# Remove lock
	rm "$lockFilePath"
	rm "$lockInfoFilePath"
}

# Bans a file on the lock server. No more locking will be allowed for this file.
# To un-ban this file just call add again.
#
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE (optinal) If the file was added/unlocked in the past it can only be banned, if the correct change-confirmation-signature is send
# @return_codes 0=success 1=failure
# @return_value ban-confirmation-signature (bcs). Only who sends this bcs can add this file again.
lockServerBan() {
	checkAtLeastParameter 5 "ban [USER_NAME] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH] [PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE]" "$@"
	user="$1"; projectName="$2"; releaseName="$3"; fileNameHash="$4"; fileContentHash="$5"
	previousChangeConfirmSignature="${6:-}"
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	lockInfoFilePath="${lockFilePath}info"
	lockBanFilePath="${lockFilePath}ban"
	lockBanInfoFilePath="${lockFilePath}baninfo"
	
	logDebug "Ban file: $lockFilePath"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if the file was already banned
	if [ -e "$lockBanFilePath" ]; then
		echo "File was already banned by $(cat "${lockBanInfoFilePath}" | sed ':a;N;$!ba;s/\n/. /g')"
		exit 1
	fi
	
	# Check if file is locked
	if [ -e "$lockFilePath" ]; then
		echo "File is locked by $(cat "${lockInfoFilePath}" | sed ':a;N;$!ba;s/\n/. /g')"
		exit 1
	fi
	
	# Check if this file was locked in the past and in that case check if the received change confirmation signature was the latest
	if [ -e "${lockFilePath}.latest" ]; then
		# Check if a change confirmation signature was send
		if [ -z "$previousChangeConfirmSignature" ]; then
			echo "File was last modified by $(cat "${lockFilePath}.latestinfo" | sed ':a;N;$!ba;s/\n/. /g'), but no change confirmation signature was sent. Get the latest version first."
			exit 1
		fi
		
		# Check if the received change confirmation signature fits to that latest change
		logDebug "Check that the received change confirmation signature fits to the last known state of this file"
		verifySignature "$LOCK_SERVER_PUBLIC_KEY_FILE" "$previousChangeConfirmSignature" "$(cat "${lockFilePath}.latest")"; validationResult=$?
		expectSuccess "File was last modified by $(cat "${lockFilePath}.latestinfo" | sed ':a;N;$!ba;s/\n/. /g'). Get the latest version first." $validationResult
	fi
	
	# Store the latest content hash as the ban content hash
	echo "${fileContentHash}-ban" > "$lockBanFilePath"
	
	# Create a ban info file
	echo "user:$user" > "$lockBanInfoFilePath"
	echo "timestamp:$(date)" >> "$lockBanInfoFilePath"
	
	# Create the ban confirmation signature for the received content hash which will be send back to the client
	# Only the client who has the ban confirmationo signature can reallow this file
	banConfirmationSignatureFile="${lockFilePath}.bcsig"
	logDebug "Create ban confirmation signature for: $(cat "${lockBanFilePath}")"
	returnValue=$(openssl dgst -sha1 -sign "$LOCK_SERVER_PRIVATE_KEY_FILE" "$lockBanFilePath" > "${banConfirmationSignatureFile}" 2>>"$LOCK_SERVER_LOG")
	
	# Check if the signature creation failed, in that case remove the ban files and return the error msg
	if [ $? -ne 0 ]; then
		rm "$lockBanFilePath"
		rm "$lockBanInfoFilePath"
		echo "Openssl error while creating the ban confirmation signature. For more details see the log file: $LOCK_SERVER_LOG"
		exit 1
	fi
	
	# Remove the latest lock files
	if [ -e "${lockFilePath}.latest" ]; then
		rm "${lockFilePath}.latest"
		rm "${lockFilePath}.latestinfo"
	fi
	
	# Encode the binary signature to base64 and remove all \n, so it can be easily transferred to the client
	banConfirmationSignature=$(cat "${banConfirmationSignatureFile}" | base64 | sed ':a;N;$!ba;s/\n//g')
	logDebug "Created ban confirmation signature: $banConfirmationSignature"
	
	# Remove the temp created ban confirmation signature file
	rm "$banConfirmationSignatureFile"
	
	echo "$banConfirmationSignature"
}