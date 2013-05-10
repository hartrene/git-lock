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

# Contains util functions for the lock-server and git-lock client.

# Checks if exactly expected parameter are passed to a function
# Print the given usage message and logs all given parameter, if the expected parameter doesn't match with the given parameter
#
# @param $1 Expected parameter count
# @param $2 Usage message
# @return_codes 0=success 1=if not all parameter are given
# @return_value Usage message if not all parameter are given
checkParameter() {
	# Calculate expected parameter cound (add the two parameter for this function 1:[Expected count] 2:[Usage statement])
	local expectParameterCount=$(($1+2))
	if [ "$#" -ne $expectParameterCount ]; then
		echo "Error: Unexpected parameter found (expected: $1 found: $(($#-2)))"
		echo "Usage: $2"
		echo "Unexpected parameter found: $2"
		
		# Print received parameter
		printReceivedParameter "$@"
		
		exit 1
	fi
}

# Checks if at least all expected parameter were passed to the function.
# Print the given usage message and logs all given parameter, if the expected parameter doesn't match with the given parameter
#
# @param $1 Expected at least parameter count
# @param $2 Usage message
# @return_codes 0=success 1=if not all parameter are given
# @return_value Usage message if not all parameter are given
checkAtLeastParameter() {
	# Calculate expected parameter count (add the two parameter for this function 1:[Expected count] 2:[Usage statement])
	local expectParameterCount=$(($1+2))
	if [ "$#" -lt $expectParameterCount ]; then
		echo "Error: Unexpected parameter found (expected at least: $1 found: $(($#-2)))"
		echo "Usage: $2"
		echo "Unexpected parameter found"
		
		# Print received parameter
		printReceivedParameter "$@"
		
		exit 1
	fi
}

# Prints all passed parameter
# @return_codes 0=success 1=failure
# @return_value nothing
printReceivedParameter() {
	local count=0
	for param in "$@"; do
		local count=$(($count+1))
		
		# Skip the first two since they are not relevant
		if [ $count -eq 1 ] || [ $count -eq 2 ]; then 
			continue; 
		fi
		
		echo "Found parameter: $param"
	done
}

# Creates the given directory if it not already exists
#
# @param DIRECTORY_TO_CREATE Directory to create
# @param CREATE_MSG Log message if the creation of the directory was successful
# @param ERROR_MSG Log message if the creation of the directory failed
# @return_codes 0=if the directory was created 1=if the directory was already there
# @return_value nothing
createDir() {
	checkParameter 3 "createDir() [DIRECTORY_TO_CREATE] [CREATE_MSG] [ERROR_MSG]" "$@"
	local directoryToCreate="$1"; local successMsg="$2"; local errorMg="$3";
	
	if [ ! -d "$directoryToCreate" ]; then
		mkdir -p "$1"
		expectSuccess "$errorMg" $?
		
		if [ -n "$successMsg" ]; then
			logInfo "$successMsg"
		fi
		
		return 0
	else
		return 1
	fi
}

# Checks if the given return_code is 0
# If the given return_code has another value, the error message will be logged and the function exit the script
#
# @param ERROR_MSG Error message
# @param RETURN_CODE_TO_CHECK Return_code to check if it is 0
# @return_codes 0=success 1=failure
# @return_value nothing
expectSuccess() {
	checkParameter 2 "expectSuccess() [ERROR_MSG] [RETURN_CODE_TO_CHECK]" "$@"
	local errorMsg="$1"; local returnCode="$2"
	
	if [ "$returnCode" -ne 0 ]; then
		echo "$errorMsg"
		exit 1
	fi
}

# Verifies the given signature against the given content.
# 
# @param PUBLIC_KEY_FILE Key file which will be used to verify the signature
# @param SIGNATURE_BASE64 Base64 encoded signature
# @param SIGNED_CONTENT Content which should fit to the passed signature
# @return_codes 0=success 1=failure
# @return_value nothing
verifySignature() {
	checkParameter 3 "verifySignature() [PUBLIC_KEY_FILE] [SIGNATURE_BASE64] [SIGNED_CONTENT]" "$@"
	local publicKeyFile="$1"; local signatureBase64="$2"; local signedContent="$3";
	
	logDebug "Validate signature: $signatureBase64 against $signedContent"
	
	local signatureTestDir="signaturetest"
	local contentFileToValidate="${signatureTestDir}/content.file"
	local signatureBase64File="${signatureTestDir}/signature.base64"
	local signatureByteFile="${signatureTestDir}/signature.byte"
	
	createDir "$signatureTestDir" "" "Error while creating directory for signature test: $signatureTestDir"
	
	# Save the content to verify to a file
	echo "$signedContent" > "$contentFileToValidate"
	# Lock the file and store the receiving signature (will be base64 encoded)
	echo "$signatureBase64" > "$signatureBase64File"
	# Restore the original signature (byte) and store it in a file
	base64 -d "$signatureBase64File" > "$signatureByteFile"
	expectSuccess "Unable to convert the received base64 content to bytes: $signatureBase64" $?
	
	# Validate the received public key and the received signature against the content hash
	returnValue=$(openssl dgst -sha1 -verify "$publicKeyFile" -signature "$signatureByteFile" "$contentFileToValidate" 1>/dev/null)
	validationSuccessful=$?
	logDebug "Validation result: $validationSuccessful"
	
	rm -rf "$signatureTestDir"
	
	return $validationSuccessful
}

# Build the hash code of the given file including the subdirectory starting from git root.
#
# @param FILE File for which the unique hash code should be created
# @return_codes 0=success 1=failure
# @return_value hash code
buildFilepathHash() {
	checkParameter 1 "buildFilepathHash() [FILE]" "$@"
	local file="$1";

	# Build the file path of the given file including the subdirectory starting from git root
	relativeFilepath=$(discoverRelativeFilepathFromGitRoot "$file")
	expectSuccess "Error while discovering the relative filepath from git root occurred: $relativeFilepath" $?
	
	logDebug "Build unique filename hash for path: $relativeFilepath"
	
	# Get the hash of the filename
	fileNameHash=$(echo "$relativeFilepath" | md5sum | cut -f1 -d' ')
	expectSuccess "Error while creating the file name hash for relativeFilepath occurred: $fileNameHash" $?
	
	echo "$fileNameHash"
}

# Discovers the subdirectory of the given file starting from git root.
#
# @param FILE File for which the subdirectory should be calculated
# @return_codes 0=success 1=failure
# @return_value
discoverRelativeFilepathFromGitRoot() {
	checkParameter 1 "discoverRelativeFilepathFromGitRoot() [FILE]" "$@"
	local file="$1";
	
	# Get the directory of the file starting from git-root
	discoverGitRoot gitRoot
		
	# Build the relative filepath
	local currentDirectory="$(pwd)/"
	local gitSubDirectory="${currentDirectory/$gitRoot/}"
	local relativeFilepath="${gitSubDirectory}/${file}"
	
	echo "$relativeFilepath"
}

# Discovers the root directory of this git repository
#
# @param RESULT_VARIABLE Variable in which the directory should be stored
# @return_codes 0=success 1=failure
# @return_value nothing
discoverGitRoot() {
	checkParameter 1 "discoverGitRoot() [RESULT_VARIABLE]" "$@"
	local resultVariable=$1; eval $resultVariable=
	
	gitRoot=$(git rev-parse --show-toplevel)
	expectSuccess "Git root can't be found. Run git-lock from within a git repo." $?
	
	if [ -n "$gitRoot" ]; then
		eval $resultVariable="'${gitRoot}/'"
	else
		eval $resultVariable="''"
	fi
}

# Acquires the named mutex
#
# @param MUTEX_NAME Name of the mutex to acquire
# @param WAIT_TIMEOUT_SECONDS Timeout to acquire this mutext, if the mutex is hold
# @param FORCE_MUTEX_RELEASE_MILLIS Break the mutex, if it is hold longer than this time
# @return_codes 0=success 1=failure
# @return_value nothing
acquireMutex() {
	checkParameter 3 "acquireMutex() [MUTEX_NAME] [WAIT_TIMEOUT_SECONDS] [FORCE_MUTEX_RELEASE_MILLIS]" "$@"
	local mutexName="$1"; local timeout="$2"; local forceMutexReleaseMillis="$3";
	
	# Check if mutex was hold longer than allowed
	mutexAcquiredTime=$(stat -c %Y "$mutexName" 2>/dev/null)
	# Check if a mutex acquired time could be found
	if [ $? = 0 ]; then
		local currentTime=$(date +"%s")
		local mutexHoldForMillis=$(($currentTime-$mutexAcquiredTime))
		if [ $mutexHoldForMillis -gt $forceMutexReleaseMillis ]; then
			releaseMutex "$mutexName"
		fi
	fi

	# Check if mutex directory can be created
	# If not wait a second and try again until timeout
	local waitTime=0
	local mutexAcquiredTimeFile="${mutexName}/time"
	until createDir "$mutexName" "" ""
	do
		if [ $waitTime -ge $timeout ]; then
			return 1;
		fi
		
		waitTime=$(($waitTime+1))
		sleep 1
	done
}

# Releases the named mutex
#
# MUTEX_NAME Name of the mutex to release
# @return_codes 0=success 1=failure
# @return_value nothing
releaseMutex() {
	checkParameter 1 "acquireMutex() [MUTEX_NAME]" "$@"
	local mutexName="$1"
	
	if [ -d "$mutexName" ]; then
		rm -r "$1";
	fi
}

# Returns and checks if the passed dirctory exists
#
# @param DIRECTORY Directory which needs to be checked
# @return_codes 0=Directory exists 1=Directory doesn't exist
# @return_value Passed Directory
checkAndReturnDir() {
	checkParameter 1 "checkAndReturnDir() [DIRECTORY]" "$@"
	local directory="$1";
	
	echo -n "$directory"
	
	if [ -d "$directory" ]; then
		return 0
	else
		echo " not found"
		return 1
	fi
}

# Checks if the passed file exists and exits the script if the file wasn't found
#
# @param FILE File which needs to be able available
# @param ERROR_MSG Error message which will be logged before exiting this script
# @return_codes 0=success 1=failure
# @return_value
expectFileExists() {
	checkParameter 2 "expectFileExists() [FILE] [ERROR_MSG]" "$@"
	local file="$1"; local errorMsg="$2";
	
	if [ ! -f "$file" ]; then
		echo "$errorMsg"
		exit 1
	fi
}

# Reads a property from the passed property file
#
# @param RESULT_VARIABLE Result variable in which the value of the property will be stored
# @param PROPERTY_FILE Property file which will be read
# @param KEY Key of the requested property
# @return_codes 0=success 1=failure
# @return_value nothing
readProperty() {
	checkParameter 3 "readProperty() [RESULT_VARIABLE] [PROPERTY_FILE] [KEY]" "$@"
	local resultVariable=$1; eval $resultVariable=
	local propertyFile="$2"; local key="$3";
	
	# Check if property file is there
	expectFileExists "$propertyFile" "Property file $propertyFile not found, unable to read property '$key'"
	
	# Check if the property is in the file
	returnValue=$(cat "$propertyFile" | grep "${key}=")
	if [ $? = 1 ]; then
		return 1
	fi
	
	returnValue=$(sed '/^\#/d' "$propertyFile" | grep "$key" | tail -n 1 | cut -d "=" -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	expectSuccess "Failure occurred while parsing property file '$returnValue'" $?
	
	eval $resultVariable="'${returnValue}'"
}

# Returns the value of a property, but exits the script if it can't be found
#
# @param RESULT_VARIABLE Result variable in which the value of the property will be stored
# @param PROPERTY_FILE Property file which will be read
# @param KEY Key of the requested property
# @return_codes 0=success 1=failure
# @return_value nothing
needProperty() {
	checkParameter 3 "needProperty() [RESULT_VARIABLE] [PROPERTY_FILE] [KEY]" "$@"
	local resultVariable=$1; eval $resultVariable=
	local propertyFile="$2"; local key="$3";
	
	readProperty propertyValue "$propertyFile" "$key"
	if [ $? = 1 ]; then
		echo "property $key in file $propertyFile not found"
		exit 1
	fi
	
	eval $resultVariable="'${propertyValue}'"
}

# Writes the value of the passed property
#
# @param PROPERTY_FILE Property file which will be modified
# @param KEY Key of the property
# @param VALUE Value of the property
# @return_codes 0=success 1=failure
# @return_value nothing
writeProperty() {
	checkParameter 3 "writeProperty() [PROPERTY_FILE] [KEY] [VALUE] " "$@"
	local propertyFile="$1"; local key="$2"; local value="$3";
	
	# Check if property file is there
	expectFileExists "$propertyFile" "Property file $propertyFile not found"
	
	# Check if the property can be added or needs to be replaced
	returnValue=$(cat "$propertyFile" | grep "${key}=")
	if [ $? -ne 0 ]; then
		echo "$key=$value" >> "$propertyFile"
	else
		returnValue=$(sed -i "s/\($key *= *\).*/\1$value/" "$propertyFile")
		expectSuccess "Adding the new property $key and value $value to file $propertyFile failed: $returnValue" $?
	fi
}

# Logs a debug message, if the log level allows
logDebug() {
	if [ $logLevel -ge $LOG_LEVEL_DEBUG ]; then
		logMessage "$1"
	fi
}

# Logs an info message, if the log level allows
logInfo() {
	if [ $logLevel -ge $LOG_LEVEL_INFO ]; then
		logMessage "$1"
	fi
}

# Logs an error message, if the log level allows
logError() {
	if [ $logLevel -ge $LOG_LEVEL_ERROR ]; then
		logMessage "$1"
	fi
}

####################################################################
# Bash v3 does not support associative arrays
# Usage: map_put map_name key value
#
mapPut() {
    alias "${1}$2"="$3"
}

# map_get map_name key
# @return value
#
mapGet() {
	alias "${1}$2" 2>/dev/null >/dev/null
    if [ $? -eq 0 ]; then
		alias "${1}$2" | awk -F "'" '{ print $2; }'
	else
		return 1
    fi
}

# map_keys map_name 
# @return map keys
#
mapKeys() {
    alias -p | grep $1 | cut -d'=' -f1 | awk -F"$1" '{print $2; }'
}