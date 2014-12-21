#!/bin/bash

# lock-server functions
#
# This script needs the following environment parameter:
#   LOCK_SERVER_BIN_DIR  Directory which contains all lock-server scripts
#   LOCK_SERVER_DIR      Working directory of this lock-server to hold the project/release folders and the lock files
#
# Available lock-server commands:
# 
# init-project [BRANCH] [PROJECT_NAME] [RELEASE_NAME]
# 	Creates a new project and release for a branch on the server
# lock [USER] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [PREVIOUS_CHANGE_CONFIRMATION_SIGNATURE]
#	Locks a file
# unlock [USER_NAME] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [FILE_CONTENT_HASH] [LOCK_CONFIRMATION_SIGNATURE]
#	Unlocks a file
# cancel [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME_HASH] [LOCK_CONFIRMATION_SIGNATURE]
#	Cancel of a lock, in case the lock change needs to be dropped
# lookup-projects
#	Logs all existing projects and releases
# lookup-project-dir
#	Returns the directory of the given project
# lookup-release-dir
#	Returns the directory of the given release
# show-user-locks
#   Shows all locks of a user
# verify-changes
#	Checks if all file changes are valid e.g. no file was changed which is locked or that no old content of a file was changed

# Import util functions
. "${LOCK_SERVER_BIN_DIR}/lock-util.sh"

LOCK_SERVER_CMD_NAME="lockServer"
LOCK_SERVER_LOG="${LOCK_SERVER_DIR}/lock-server.log"
LOCK_SERVER_MUTEX_NAME="${LOCK_SERVER_DIR}/.mutex"
LOCK_SERVER_LOG_PREFIX="[Lock-Server] "
LOCK_SERVER_BRANCH_DETAILS_FILE="${LOCK_SERVER_DIR}/branch_details"

# Main function which dispatches calls to all lock-server functions
# This function gets called from lock-server.sh which gets called from a client via ssh or it gets called directly from the unit-tests.
#
# To avoid parallel execution errors of the lock-server functions, it will request a mutex in the beginning to block all other requests.
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
	# Make sure that the mutex gets removed if the program exits abnormally or got killed
	trap "releaseMutex $LOCK_SERVER_MUTEX_NAME; exit" INT TERM EXIT
	
	# Shift the input variables so that the next function won't get the command ($2 becomes $1...)
	shift
	
	# Dispatch the incomming command to the correct function
	case "$command" in
		init-project) lockServerInitProject "$@";;
		lock) lockServerLock "$@";;
		unlock) lockServerUnlock "$@";;
		cancel) lockServerCancel "$@";;
		show-user-locks) lockServerShowUserLocks "$@";;
		all-locks) lockServerShowAllLocks "$@";;
		lookup-projects) lockServerLookupProjects "$@";;
		verify-changes) lockServerVerifyChanges "$@";;
		
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
# @param BRANCH Branch for which this project/release will be used
# @param PROJECT_NAME Name of the new project
# @param RELEASE_NAME Name of the new release
# @return_codes 0=success 1=failure
# @return_value
lockServerInitProject() {
	checkParameter 3 "init-project [BRANCH] [PROJECT_NAME] [RELEASE_NAME]" "$@"
	branch="$1"; projectName="$2"; releaseName="$3";
	logInfo "Init project $projectName and release $releaseName for branch $branch"
	
	if [ -e "${LOCK_SERVER_DIR}/${projectName}" ]; then
		logInfo "Project already exists"
	else
		# Create project dir if not yet exists
		createDir "${LOCK_SERVER_DIR}/${projectName}" "Created new project directory on lock server: ${LOCK_SERVER_DIR}/${projectName}" "Unable to create the project directory: ${LOCK_SERVER_DIR}/${projectName}"
	fi
	
	if [ -e "${LOCK_SERVER_DIR}/${projectName}/${releaseName}" ]; then
		logInfo "Release already exists"
	else
		# Create release dir if not yet exists
		createDir "${LOCK_SERVER_DIR}/${projectName}/${releaseName}" "Created new release directory: ${LOCK_SERVER_DIR}/${projectName}/${releaseName}" "Unable to create the release directory: ${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	fi
	
	# Store branch details
	lockServerStoreBranchDetails "$branch" "$projectName" "$releaseName"
	
	return 0
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

# Locks a file.
#
# @param USER Name of the user who would like to lock file
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param FILE_CONTENT_HASH Hash of the content of the file to lock
# @return_codes 0=success 1=failure
# @return_value Returns by who and when the file was locked
lockServerLock() {
	checkAtLeastParameter 5 "lock [USER] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME] [FILE_CONTENT_HASH]" "$@"
	user="$1"; projectName="$2"; releaseName="$3"; fileName="$4"; fileContentHash="$5";
	previousChangeConfirmSignature="${5:-}"
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileName")
	expectSuccess "Error while creating the file name hash occurred: $fileName" $?
	
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	logDebug "Lock file: $fileName"
	logDebug "Store lock info at: $lockFilePath"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if file is locked
	if [ -e "$lockFilePath" ]; then
		echo "File is already locked by $(cat "${lockFilePath}" | sed ':a;N;$!ba;s/\n/. /g')"
		exit 1
	fi
	
	# Check if this file was locked in the past and in that case check if the received content hash is the latest
	if [ -e "${lockFilePath}.latest" ]; then
		# Check if the received content hash is the latest known
		latestHashAfterUnlock=$(cat "${lockFilePath}.latest")
		if [ "$fileContentHash" != "$latestHashAfterUnlock" ]; then
			latestInfoFile="${lockFilePath}.latestinfo"
			user=$(sed -n "1p" "$latestInfoFile" | cut -d ":" -f2)
			file=$(sed -n "2p" "$latestInfoFile" | cut -d ":" -f2)
			timestamp=$(sed -n "3p" "$latestInfoFile" | cut -d ":" -f2-5)
			echo "File was already modified by $user at $timestamp. Get the latest version first."
			exit 1
		fi
	fi
	
	# Create new lock entry for this file
	echo "user:$user" > "$lockFilePath"
	echo "file:$fileName" >> "$lockFilePath"
	echo "timestamp:$(date)" >> "$lockFilePath"
	
	# Store the content hash at the time of locking
	echo "$fileContentHash" > "${lockFilePath}.latest"
	
	logDebug "Lock complete"
}

# Unlocks a file.
#
# @param USER Name of the user who would like to unlock the file
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param FILE_CONTENT_HASH Hash of the new content of the file at time of unlock
# @return_codes 0=success 1=failure
# @return_value change-confirmation-signature (ccs). Only who sends this ccs can lock this file again.
lockServerUnlock() {
	checkParameter 5 "unlock [USER_NAME] [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME] [FILE_CONTENT_HASH]" "$@"
	user="$1"; projectName="$2"; releaseName="$3"; fileName="$4"; fileContentHash="$5";
	logDebug "Unlock file: $fileName"
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileName")
	expectSuccess "Error while creating the file name hash occurred: $fileName" $?
	
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	logDebug "Unlock file path: $lockFilePath"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if file is locked
	if [ ! -e "$lockFilePath" ]; then
		echo "File is not locked"
		exit 1
	fi
	
	# Delete lock files
	rm "$lockFilePath"
	
	# Save the received content hash, so that we are able to figure out the next time someone likes to lock this file, that he is not trying to modify an old version
	latestLockFilePath="${lockFilePath}.latest"
	logDebug "Store received content hash $fileContentHash at: $latestLockFilePath"
	echo "$fileContentHash" > "$latestLockFilePath"
	
	# Save the details who did and when was the latest change
	latestChangeInfoFile="${lockFilePath}.latestinfo"
	receivedUnlockTimestamp=$(date)
	logDebug "Store latest lock info: user=$user; file:$fileName; timestamp:$receivedUnlockTimestamp; at: $latestChangeInfoFile"
	echo "user:$user" > "$latestChangeInfoFile"
	echo "file:$fileName" >> "$latestChangeInfoFile"
	echo "timestamp:$receivedUnlockTimestamp" >> "$latestChangeInfoFile"
	
	logDebug "Unlock complete"
}

# Cancel of a lock, in case the lock change needs to be dropped.
#
# @param PROJECT_NAME Project to which this file belongs
# @param RELEASE_NAME Release to which this file belongs
# @param FILE_NAME_HASH Hash of the filename (the hash should be created for the path+filename)
# @param FILE_CONTENT_HASH Hash of the content of the file at time of cancel
# @return_codes 0=success 1=failure
# @return_value nothing
lockServerCancel() {
	checkParameter 4 "cancel [PROJECT_NAME] [RELEASE_NAME] [FILE_NAME] [FILE_CONTENT_HASH]" "$@"
	projectName="$1"; releaseName="$2"; fileName="$3"; fileContentHash="$4"
	logDebug "Cancel lock of file: $fileName"
	
	# Get the hash of the filename
	fileNameHash=$(buildFilepathHash "$fileName")
	expectSuccess "Error while creating the file name hash occurred: $fileName" $?
	
	lockFilePath="${LOCK_SERVER_DIR}/${projectName}/${releaseName}/${fileNameHash}.lock"
	lockInfoFilePath="${lockFilePath}info"
	
	# Check if init was running
	test -d "${LOCK_SERVER_DIR}/${projectName}/${releaseName}"
	expectSuccess "Project $projectName and release $releaseName is not setup on lock-server, run init first" $?
	
	# Check if file is locked
	if [ ! -e "$lockFilePath" ]; then
		echo "File is not locked"
		exit 1
	fi
	
	# Verify the received content hash is the same as it was when the file was locked (make sure no changed has happened)
	hashAtLock=$(cat "${lockFilePath}.latest")
	if [ "$fileContentHash" != "$hashAtLock" ]; then
		echo "File was already modified on the client. Revert changes and then cancel again. newHash=$fileContentHash hashAtLock=$hashAtLock"
		exit 1
	fi
	
	expectSuccess "Error: Validation of the received lock signature failed" $?
	
	# Remove lock
	rm "$lockFilePath"
}

# Shows the locks of a particular user.
#
# @param USER Name of a user
# @return_codes 0=success 1=failure
# @return_value List of files which the user has locked or a messages that the user doesn't have any locks
lockServerShowUserLocks() {
	checkParameter 1 "show-user-locks [USER]" "$@"
	user="$1"
	logDebug "Get locks of user: $user"
	logDebug "Look in directory: $LOCK_SERVER_DIR"
	files=$(find $LOCK_SERVER_DIR -name "*.lock" -type f -print0 | xargs -0 grep -A1 -n "user:$user" /dev/null | grep file | cut -d ":" -f2)
	if [ "$files" == "" ]; then
		echo "User has no locks"
	else
		echo "$files"
	fi
}

# Stores the project/release for a branch into a property file on the server.
# This information is being used to check if files are locked for a specific project/release.
#
# @param BRANCH branch for which the details should be stored
# @param PROJECT project of this branch
# @param RELEASE release of this branch
# @return_codes 0=success 1=failure
# @return_value nothing
lockServerStoreBranchDetails() {
	checkParameter 3 "storeBranchDetails() [BRANCH] [PROJECT] [RELEASE]" "$@"
	local branch="$1"; local project="$2"; local release="$3"
		
	if [ ! -e "$LOCK_SERVER_BRANCH_DETAILS_FILE" ]; then
		logDebug "Create git-lock branches file: $LOCK_SERVER_BRANCH_DETAILS_FILE"
		returnValue=$(touch "$LOCK_SERVER_BRANCH_DETAILS_FILE")
		expectSuccess "Git-lock branches file can't be created: $returnValue" $?
	fi
	
	branchDetails=$(cat $LOCK_SERVER_BRANCH_DETAILS_FILE | grep "$branch")
	logDebug "Found branch details for branch $branch: $branchDetails"
	
	if [ "$branchDetails" = "" ]; then
		logDebug "Couldn't find any branch details yet; add new line"
		echo "$branch:$project/$release" >> "$LOCK_SERVER_BRANCH_DETAILS_FILE"
	else
		logDebug "Found branch details already; replace line"
		sed -i "s/$branch:.*/$branch:$project\/$release/" "$LOCK_SERVER_BRANCH_DETAILS_FILE"
	fi
}

# Gets the project/release of a branch.
#
# @param BRANCH branch for which the project/release should be returned
# @return_codes 0=success 1=failure
# @return_value project/release of the branch
lockServerGetBranchDetails() {
	checkParameter 1 "getBranchDetails() [BRANCH]" "$@"
	local branch="$1"
	if [ ! -e "$LOCK_SERVER_BRANCH_DETAILS_FILE" ]; then
		expectSuccess "Branch could not be found in $LOCK_SERVER_BRANCH_DETAILS_FILE: $branchDetails" 1
	fi
	branchDetails=$(cat $LOCK_SERVER_BRANCH_DETAILS_FILE | grep "$branch")
	expectSuccess "Branch could not be found: $branchDetails" $?
	logDebug "Found branch details: $branchDetails"
	result=$(echo $branchDetails | cut -d ":" -f2)
	echo "$result"
}

# Returns the locks of all user.
#
# @return_codes 0=success 1=failure
# @return_value List of all locked files or a messages that no user has any locks
lockServerShowAllLocks() {
	checkParameter 0 "all-locks" "$@"
	logDebug "Get locks of all user"
	logDebug "Look in directory: $LOCK_SERVER_DIR"
	files=$(find $LOCK_SERVER_DIR -name "*.lock" -type f -print0 | xargs -0 grep -A2 -n "" /dev/null)
	if [ "$files" != "" ]; then
		logDebug "Found locked files"
		IFS=$'\n'
		for file in $files; do
			if [ "$file" == "--" ]; then
				lockedFile=""; project=""; user=""
			elif [[ "$file" == *":user:"* ]]; then
				local relativePath="${file/${LOCK_SERVER_DIR}\//}"
				project=$(echo $relativePath | cut -d "/" -f1-2)
				user=$(echo $file | cut -d ":" -f4)
			elif [[ "$file" == *":file:"* ]]; then
				lockedFile=$(echo $file | cut -d ":" -f4)
			elif [[ "$file" == *":timestamp:"* ]]; then
				timestamp=$(echo $file | cut -d ":" -f4-6)
				echo "$lockedFile -- locked by $user for project $project since $timestamp"
			else
				echo "Found unexpected line in lock file: $file"
				exit 1
			fi
		done
	else
		echo "No locks found."
	fi
}

# Verify changes which a client received from a push.
#
# @param List of changes: [BRANCH CHANGE_BIT FILENAME_HASH CONTENT_HASH] e.g. -> master A 3bc3be114fb6323adc5b0ad7422d193a e69de29bb2d1d6434b8b29ae775ad8c2e48c5391
# @return_codes 0=success 1=failure
# @return_value Error message which file change caused the problem
lockServerVerifyChanges() {
	local changeCount=1
	for changeBit in $@; do
		logDebug "Found: $changeCount $changeBit"
		if [ "$changeCount" = "1" ]; then
			branch="$changeBit"
		elif [ "$changeCount" = "2" ]; then
			changeFlag="$changeBit"
		elif [ "$changeCount" = "3" ]; then
			filenameHash="$changeBit"
		else
			contentHash="$changeBit"
			returnValue=$(lockServerVerifyChange "$branch" "$changeFlag" "$filenameHash" "$contentHash")
			expectSuccess "Verification failed: $returnValue" $?
			changeCount=0
		fi
		changeCount=$(($changeCount+1))
	done
}

# Verifies one file change which a client received from a push.
#
# @param BRANCH Branch in which this file was changed (needed to pick the right release/project)
# @param CHANGE_FLAG Flag if the file was A=ADDED or M=Modified or D=DELETED
# @param FILENAME_HASH Hash of the filename
# @param CONTENT_HASH Received content hash of the file
# @return_codes 0=success 1=failure
# @return_value Error message why this change isn't valid
lockServerVerifyChange() {
	checkParameter 4 "lockServerVerifyChange [BRANCH] [CHANGE_FLAG] [FILENAME_HASH] [CONTENT_HASH]" "$@"
	branch="$1"; changeFlag="$2"; fileNameHash="$3"; contentHash="$4"
	logDebug "Verify change: $branch $changeFlag $fileNameHash $contentHash"
	
	# Get error message
	case "$changeFlag" in
		A) change="Added";;
		M) change="Modified";;
		D) change="Deleted";;
	esac
	
	# Get the project/release of this branch
	projectRelease=$(lockServerGetBranchDetails "$branch")
	expectSuccess "Branch details for branch $branch couldn't be found; run git-lock init or git-lock switch-project for this branch first." $?
	
	# Get possible lock file path
	lockFilePath="${LOCK_SERVER_DIR}/${projectRelease}/${fileNameHash}.lock"
	logDebug "Check if file is locked at: $lockFilePath"
	
	# Check if changed file is locked
	if [ -e "$lockFilePath" ]; then
		logDebug "File is locked"
		user=$(sed -n "1p" "$lockFilePath" | cut -d ":" -f2)
		file=$(sed -n "2p" "$lockFilePath" | cut -d ":" -f2)
		timestamp=$(sed -n "3p" "$lockFilePath" | cut -d ":" -f2)
		expectSuccess "$change file $file is locked by $user since $timestamp. Please unlock first and push again." 1
	else
		logDebug "File is not locked"
	fi
	
	# Latest hash info file
	latestFilePath="${LOCK_SERVER_DIR}/${projectRelease}/${fileNameHash}.lock.latest"
	logDebug "Look if latest content hash was received at: $latestFilePath"
	if [ -e "$latestFilePath" ]; then
		latestHash=$(cat "$latestFilePath")
		logDebug "Compare received content hash: $contentHash with latest stored content hash: $latestHash"
		if [ ! "$contentHash" = "$latestHash" ]; then
			logDebug "Didn't receive the latest content hash"
			latestInfoFilePath="${LOCK_SERVER_DIR}/${projectRelease}/${fileNameHash}.lock.latestinfo"
			if [ -e "$latestFilePath" ]; then
				user=$(sed -n "1p" "$latestInfoFilePath" | cut -d ":" -f2)
				file=$(sed -n "2p" "$latestInfoFilePath" | cut -d ":" -f2)
				timestamp=$(sed -n "3p" "$latestInfoFilePath" | cut -d ":" -f2-5)
				expectSuccess "$change file $file is not the latest version. Please get the latest version first and then push again. Last changed received from user $user at $timestamp" 1
			else
				expectSuccess "Didn't receive the latest content hash for file $fileNameHash and couldn't find latest info file to give a meaningful error message. Missing file: $latestInfoFilePath" 1
			fi
		else
			logDebug "Latest content hash received -> ok"
		fi
	else
		logDebug "File was never locked"
	fi
}
