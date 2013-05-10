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

# Base functions for all hook related scripts

# Set if log info is set
LOG_LEVEL_QUIET=0
LOG_LEVEL_ERROR=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3
logLevel=$LOG_LEVEL_ERROR

# Check if a log level was given
param="${1:-}"
if [ -n "$param" ]; then
	case "$param" in
		--quiet) logLevel=$LOG_LEVEL_QUIET; shift;;
		--error) logLevel=$LOG_LEVEL_ERROR; shift;;
		--info) logLevel=$LOG_LEVEL_INFO; shift;;
		--debug) logLevel=$LOG_LEVEL_DEBUG; shift;;
	esac
fi

# Function to log all output directly with echo
logMessage() {
	echo "$1"
}

receivePublicKeyFromLockServer() {
	local resultVariable=$1; eval $resultVariable=
	logDebug "Try to receive the lock-servers public-key"
	
	local serverPublicKeyTargetPath="$gitRoot.lock-server.public_key"
	
	# Check if the public-key is already there
	if [ -e "$serverPublicKeyTargetPath" ]; then
		logDebug "public-key is already in place, no need to lookup: $serverPublicKeyTargetPath"
	else
		# Find the lock-servers public certificate
		type git-lock &> /dev/null
		if [ $? -eq 0 ] && [ -n "$gitRoot" ]; then
			# Git commit running on a client within a git repository
			logDebug "Hook is running in a git-lock repository"
			
			logDebug "Connect to lock-server to get the public-key"
			returnValue=$(git-lock lookup-server-pubkey "$serverPublicKeyTargetPath")
			if [ $? -eq 0 ]; then
				logDebug "Received and stored the public-key: $serverPublicKeyTargetPath"
			else
				logError "Error: Unable to retrieve the public key from the lock-server: $returnValue"
				exit 1
			fi
		elif [ -n "$LOCK_SERVER_DIR" ]; then
			# Git commit running on the lock-server
			logDebug "Hook is running on a lock-server, copy the public-key directly"
			cp "${LOCK_SERVER_DIR}/.keys/.public_key" "$serverPublicKeyTargetPath"
		else
			logDebug "Hook is running in a bare repository, check if git-lock is in the path and if the .git-lock.properties was committed"
			
			# If this hooks runs within a bare repository, then try to find the git-lock-properties file in the repo
			# With that we can connect to the lock-server and receive the public-key
			# The only requirement on top of the committed properties file is that git-lock needs to be in the path
			gitLockProperties=$(discoverFileContent ".git-lock.properties" "" "" 1)
			isGitLockPropertiesAvailable=$?
			type git-lock &> /dev/null
			if [ $? -eq 0 ] && [ $isGitLockPropertiesAvailable -eq 0 ]; then
				logDebug "Found git-lock and .git-lock.properties"
			
				# Store the git-lock properties so that git-lock can access it
				echo "$gitLockProperties" >> ".git-lock.properties"
				# Make sure the temp properties file gets deleted on exit
				trap "rm .git-lock.properties; exit" INT TERM EXIT
			
				logDebug "Connect to lock-server to get the public-key"
					
				returnValue=$(git-lock lookup-server-pubkey "$serverPublicKeyTargetPath")
				if [ $? -eq 0 ]; then
					logDebug "Received and stored the public-key: $serverPublicKeyTargetPath"
				else
					logError "Error: Unable to retrieve the public key from the lock-server: $returnValue"
					exit 1
				fi
			else
				logError "ERROR: This hook is neither running on a correctly set-up git-lock client, server nor could the git-lock.properties file be found. "
				exit 1	
			fi
		fi
	fi
	
	eval $resultVariable="'${serverPublicKeyTargetPath}'"
}

# Searches for a file with a specific prefix and suffix.
# First it checks if the file is included in the git commit tree and then it checks the git working tree.
#
# @param FILENAME File to find (can include n subdirectories of the git repository)
# @param FILENAME_PREFIX Prefix which will be added to the filepath before searching for it
# @param FILENAME_SUFFIX Suffix which will be added to the filepath before searching for it
# @param CHECK_GIT_WORKING_DIR Flag (0|1) if the git working tree should be checked as well
# @return_codes 0=success 1=failure
# @return_value 0=Content of the requested file 1=Passed FILENAME
discoverFileContent() {
	checkParameter 4 "discoverFileContent() [FILENAME] [FILENAME_PREFIX] [FILENAME_SUFFIX] [CHECK_GIT_WORKING_DIR]" "$@"
	filename="$1"; filenamePrefix="$2"; filenameSuffix="$3"; checkGitWorkingDir="$4";
	
	# Build expected filename (mysubdir/myfile.xls -> mysubdir/[+PREFIX]myfile.xls[+SUFFIX] -> mysubdir/.myfile.xls.lock-change-confirm)
	# If the filename contains a '/' then we have to insert the prefix after the last '/'
	if [ "$filename" != "${filename/\//}" ]; then
		filenameToSearch="$(echo "$filename" | sed -e "s:\(.*\)\/:\1\/${filenamePrefix}:")${filenameSuffix}"
	else
		filenameToSearch="${filenamePrefix}${filename}${filenameSuffix}"
	fi
	
	# Check if the searched file will be committed as well, or if the file is available in the working dir
	filenameToSearchHash=$(echo "$filenameToSearch" | md5sum | cut -f1 -d' ')
	changeFlag=$(mapGet changeflags "$filenameToSearchHash")
	fileContentHash=$(mapGet objecthashes "$filenameToSearchHash")
	if [ $? -eq 0 ]; then
		# Ignore this file if it was deleted
		if [ ! "$changeFlag" = "D" ]; then
			# searched file will be committed as well
			echo "$(git show $fileContentHash)"
			return 0
		fi
	elif [ -n "$gitRoot" ] && [ "$checkGitWorkingDir" -eq 0 ]; then
		# Try to find the file in the current working tree
		workingDirFilePath="${gitRoot}${filenameToSearch}"
		if [ -e "$workingDirFilePath" ]; then
			echo "$(cat "$workingDirFilePath")"
			return 0
		fi
	else
		# Check against what we have to compare to get the git repository content
		git rev-parse --verify HEAD &> /dev/null
		if [ $? = 0 ]; then 
			against=HEAD
		else
			# Initial commit: diff against an empty tree object
			against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
		fi

		# Find the file in the git repository
		fileContentHash=$(git ls-tree --full-tree -r $against | grep "[[:space:]]${filenameToSearch}$" | sed -re 's/[^\t]* [^\t]* ([^\t]*).*$/\1/')
		if [ -n "$fileContentHash" ]; then
			# searched file exists in the git repository
			echo "$(git show $fileContentHash)"
			return 0
		fi
	fi
	
	echo "$filenameToSearch"
	return 1
}

# Checks if this file was ever added for locking or removed from being lockable
#
# @param FILE File to check
# @return_codes 0=file is lockable 1=file was never locked
# @return_value nothing
isFileLockable() {
	checkParameter 1 "isFileLockable() [FILE]" "$@"
	filename="$1"

	local lockFileSuffixe=(
		".lock"
		".lock-change-confirm"
		".lock-remove-confirm"
	)
	
	for lockFileSuffix in "${lockFileSuffixe[@]}"; do
		lockableFile=$(discoverFileContent "$filename" "." "$lockFileSuffix" 0)
		if [ $? -eq 0 ]; then
			return 0
		fi
	done
	
	return 1
}

# Verifies if the content change was authorized be the lock-server
#
# @param FILE File to verify
# @param SIGNATURE_FILENAME_PREFIX Prefix of the signature file
# @param SIGNATURE_FILENAME_SUFFIX Suffix of the signature file
# @param CHANGED_CONTENT New content of the file after the change which needs to be authorized by the lock-server
# @param CHANGE_DESCRIPTION Description if the file was changed or removed (just for improve the logging)
# @return_codes 0=successful 1=verification failed
# @return_value nothing
verifyContentChange() {
	checkParameter 5 "verifyContentChange() [FILE] [SIGNATURE_FILENAME_PREFIX] [SIGNATURE_FILENAME_SUFFIX] [CHANGED_CONTENT] [CHANGE_DESCRIPTION]" "$@"
	filename="$1"; signatureFilenamePrefix="$2"; signatureFilenameSuffix="$3"; changedContent="$4"; changeDescription="$5"
	
	# Receive the servers public key to be able to verify the change-signatures
	receivePublicKeyFromLockServer serverPublicKeyPath
	expectSuccess "Failed to store the servers public key: $serverPublicKeyPath" $?
	
	# Try to find the signature
	signature=$(discoverFileContent "$filename" "$signatureFilenamePrefix" "$signatureFilenameSuffix" 1)
	if [ $? -ne 0 ]; then
		echo "Error: Lockable file '$filename' was ${changeDescription}d, but the ${changeDescription}-confirmation-file '$signature' wasn't added to commit."
		echo "Add the ${changeDescription}-confirmation-signature '$signature' file and commit again."
		exit 1
	fi
	
	# Verify the signature against the new content
	verifySignature "$serverPublicKeyPath" "$signature" "$changedContent"
	if [ $? -ne 0 ]; then
		echo "Verification of the ${changeDescription}d file '$filename' failed."
		exit 1
	else
		logDebug "Change confirmation is valid"
	fi
}

# Get all file changes of this commit and store the filename+object-hash+change-flag in a map
# @param COMMAND Command to execute to get the changes of this commit
discoverCommitChanges() {
	checkParameter 1 "discoverCommitChanges() [COMMAND]" "$@"
	command="$1"
	
	logDebug "discoverCommitChanges"
	
	IFS=$'\n'
	for diffLine in $(eval $command); do
	
		logDebug "Process commit: $diffLine"

		unset IFS
		diffstatcount=1
		for diffstat in $diffLine; do
		
			case $diffstatcount in
				3) oldContentHash="$diffstat";;
				4) newContentHash="$diffstat";;
				5) changeFlag="$diffstat";;
				6) filename="$diffstat";;
			esac
			
			if [ $diffstatcount -gt 6 ]; then
				filename="$filename $diffstat"			
			fi
			
			diffstatcount=$(($diffstatcount+1))
		done
		
		filenameHash=$(echo "$filename" | md5sum | cut -f1 -d' ')
		mapPut filenames "$filenameHash" "$filename"
		mapPut changeflags "$filenameHash" "$changeFlag"
		
		if [ "$changeFlag" = "D" ]; then
			mapPut objecthashes "$filenameHash" "$oldContentHash"
		else
			mapPut objecthashes "$filenameHash" "$newContentHash"
		fi
		
	done
}

# Check if a lock status file was committed (lock-change-confirm or lock-remove-confirm).
# In that case the lockable file needs to be commmitted as well.
#
# @param FILE File to check if it is a lock status file with the passed suffix (CHECK_FILE_WITH_PREFIX)
# @param CHECK_FILE_WITH_SUFFIX Indicator if this is a lock status file to look at
# @param EXPECT_DEPENDENT_FILE_COMMIT_FLAG If this is a lock status file, check if the lockable file was committed with this expected change flag (e.g. D for delete)
# @returnCode exits with 1 in case the expected file was not committed
# @return nothing
checkCommitOfDependentFile() {
	checkParameter 3 "checkCommitOfDependentFile() [FILE] [CHECK_FILE_WITH_SUFFIX] [EXPECT_DEPENDENT_FILE_COMMIT_FLAG]" "$@"
	file="$1"; checkSuffix="$2"; expectCommitFlag="$3";

	echo "$file" | grep "${checkSuffix}$" > /dev/null
	if [ $? -eq 0 ];then
		logDebug "File is a confirmation for a lock change, check that the lockable file was comitted as well"
		
		lockableFilename=$(echo "$file" | sed -re "s/^.(.*)${checkSuffix}$/\1/")
		lockableFileHash=$(echo "$lockableFilename" | md5sum | cut -f1 -d' ')
		changeFlag=$(mapGet changeflags "$lockableFileHash")
		if [ -z "$changeFlag" ] || [ "$expectCommitFlag" = "${expectCommitFlag/$changeFlag/}" ]; then
			echo "Error: The lock status file '$filename' was committed, but the lockable file itself '$lockableFilename' was not committed with the expected change flag '$expectCommitFlag'"
			exit 1
		fi
	fi
}

# Iterates over all committed files and checks if they are lockabled.
# If so, it checks if the file was changed or removed:
#
# 1. If a lockable file was added, then check the change confirmation signature
# 2. If a lockable file was changed, then check the change confirmation signature
# 3. If a lockable file was deleted, then check the remove confirmation signature
checkFileChanges() {

	# Iterate over all committed files
	for filenameHash in $(mapKeys filenames); do
		filename=$(mapGet filenames "$filenameHash")
		changeflag=$(mapGet changeflags "$filenameHash")
		objecthash=$(mapGet objecthashes "$filenameHash")
		
		logDebug "Check file: '$filename'"
		
		# Check if this is a lock-change-confirm file, than check if the changed file was added or modified in that commit
		checkCommitOfDependentFile "$filename" ".lock-change-confirm" "A||M"
		
		# Check if this is a lock-remove-confirm file, than check if the removed file was removed in that commit
		checkCommitOfDependentFile "$filename" ".lock-remove-confirm" "D"
		
		# Check if this file is lockable
		lockableFile=$(isFileLockable "$filename")
		if [ $? -eq 0 ]; then
			logDebug "a lockable file was changed"
		else
			logDebug "file is not lockable"
			continue
		fi
		
		# Check if the file is locked
		possibleLockFile=$(discoverFileContent "$filename" "." ".lock" 0)
		if [ $? -eq 0 ]; then
			echo "Error: Unable to commit the locked file '$filename'. Unlock or cancel the lock first."
			exit 1
		fi
		
		# Check if the change was authorized by the lock-server
		case "$changeflag" in
			A) verifyContentChange "$filename" "." ".lock-change-confirm" "${objecthash}" "change";;
			M) verifyContentChange "$filename" "." ".lock-change-confirm" "${objecthash}" "change";;
			D) verifyContentChange "$filename" "." ".lock-remove-confirm" "${objecthash}-ban" "remove";;
		esac
		
	done
}