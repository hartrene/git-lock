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


# Base functions for all client related unit tests

# Import test util functions
. ./unit-test-util.sh "$@"

export LOCK_CLIENT_TEST_DIR="${TEST_EXECUTION_DIR}/client-test"
export LOCK_CLIENT_BIN_DIR="$(pwd)/../"
LOCK_CLIENT_PROPERTY_FILE="${LOCK_CLIENT_TEST_DIR}/.git-lock.properties"
LOCK_SERVER_SSH_COMMAND="$(pwd)/../lock-server.sh"

if [ $logLevel -eq $LOG_LEVEL_QUIET ]; then
	LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND --quiet"
fi
export LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND"

TEST_PROJECT_NAME="my Project"
TEST_RELEASE_NAME="a 01"
TEST_REMOTE_USER="UNKNOWN REMOTE USER"
TEST_SERVER_ADDRESS="UNKNOWN_SERVER"
TEST_SERVER_SSH_PORT="UNKNOWN_SSH_PORT"
TEST_FILE="my precious binary.xls"

# Import util functions
. ../lock-util.sh

# Import the client functionality
. ../lock-client-lib.sh

# Run before each test
setUp() {
	# Delete test dir before each test
	rm -rf "$TEST_EXECUTION_DIR"
	
	# Create and change into the test directory
	createDir "$LOCK_CLIENT_TEST_DIR" "" "Failed to create test directory: $LOCK_CLIENT_TEST_DIR"
	cd "$LOCK_CLIENT_TEST_DIR"
	
	# Set the required server properties
	export LOCK_SERVER_BIN_DIR="${LOCK_CLIENT_BIN_DIR}"
	export LOCK_SERVER_DIR="${LOCK_CLIENT_TEST_DIR}/server-test"
}

# Run once after all tests are run
oneTimeTearDown() {
	if [ -d "$TEST_EXECUTION_DIR" ]; then
		rm -rf "$TEST_EXECUTION_DIR"
	fi
}

initProject() {
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete sucessfull: $returnValue" 0 $?
}

initGitLock() {
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete sucessfull: $returnValue" 0 $?
}

lockFile() {
	checkParameter 2 "lockFile() [FILE_NAME] [FILE_CONTENT]" "$@"
	local fileName="$1"; local fileContent="$2";
	
	initProject
	
	# Make file writable if already exists
	if [ -e "$fileName" ]; then
		chmod u+w "$fileName"
	fi
	
	# Create test file
	echo "$fileContent" > "$fileName"
	
	# Acquire lock from server
	returnValue=$(lockClient lock "$fileName")
	assertEquals "Lock should have run successfully: $returnValue" 0 $?
}

checkAllRequiredProperties() {
	checkProperty "PROJECT" "$TEST_PROJECT_NAME"
	checkProperty "RELEASE" "$TEST_RELEASE_NAME"
	checkProperty "REMOTE_USER" "$TEST_REMOTE_USER"
	checkProperty "SERVER_ADDRESS" "$TEST_SERVER_ADDRESS"
	checkProperty "SSH_PORT" "$TEST_SERVER_SSH_PORT"
}

checkProperty() {
	checkParameter 2 "checkProperty() [PROPERTY_KEY] [EXPECTED_PROPERTY_VALUE]" "$@"
	local propertyKey="$1"; local expectedPropertyValue="$2";
	
	logDebug "check existence of property: $propertyKey"
	readProperty receivedPropertyValue "$LOCK_CLIENT_PROPERTY_FILE" "$propertyKey"
	assertEquals "After setting the $propertyKey property it should be in the property file: $receivedPropertyValue" 0 $?
	assertEquals "After setting the $propertyKey with value $expectedPropertyValue it should be in there" "$expectedPropertyValue" "$receivedPropertyValue"
}

askForInput() {
	checkParameter 1 "askForInput() [QUESTION]" "$@"
	local question="$1"
	
	case "$question" in
		*project*)	echo "$TEST_PROJECT_NAME";;
		*release*) 	echo "$TEST_RELEASE_NAME";;
		*user*) 	echo "$TEST_REMOTE_USER";;
		*address*) 	echo "$TEST_SERVER_ADDRESS";;
		*port*) 	echo "$TEST_SERVER_SSH_PORT";;
		*)
			echo "Requested value couldn't be found: $question" > /dev/tty
			exit 1;;
	esac
}