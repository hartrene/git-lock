#!/bin/bash

# Base functions for all client related unit tests

# Import test util functions
. ./unit-test-util.sh "$@"

export LOCK_CLIENT_TEST_DIR="${TEST_EXECUTION_DIR}/client-test"
export LOCK_CLIENT_BIN_DIR="$(pwd)/../"
LOCK_CLIENT_PROPERTY_FILE="${LOCK_CLIENT_TEST_DIR}/.git/git-lock.properties"
LOCK_SERVER_SSH_COMMAND="$(pwd)/server-test-ssh.sh $(pwd)"

if [ $logLevel -eq $LOG_LEVEL_QUIET ]; then
 	LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND"
fi
export LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND"

GIT_USER="Alice A"
ANOTHER_GIT_USER="Bob B"
TEST_PROJECT="my Project"
TEST_RELEASE="a 01"
TEST_REMOTE_USER="UNKNOWN REMOTE USER"
TEST_SERVER_ADDRESS="UNKNOWN_SERVER"
TEST_SERVER_SSH_PORT="UNKNOWN_SSH_PORT"
TEST_FILE="my precious binary.xls"
TEST_FILE_2_DIR="te st"
TEST_FILE_2="$TEST_FILE_2_DIR/te st2.xls"

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
	git config user.name "$GIT_USER"
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
	# Create test file
	echo "$fileContent" > "$fileName"
	# Acquire lock from server
	returnValue=$(lockClient lock "$fileName")
	assertEquals "Lock should have run successfully: $returnValue" 0 $?
}

checkAllRequiredPropertiesAreSetup() {
	checkProperty "PROJECT" "$TEST_PROJECT"
	checkProperty "RELEASE" "$TEST_RELEASE"
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
		*project*)	echo "$TEST_PROJECT";;
		*release*) 	echo "$TEST_RELEASE";;
		*user*) 	echo "$TEST_REMOTE_USER";;
		*address*) 	echo "$TEST_SERVER_ADDRESS";;
		*port*) 	echo "$TEST_SERVER_SSH_PORT";;
		*)
			logError "Requested value couldn't be found: $question"
			exit 1;;
	esac
}
