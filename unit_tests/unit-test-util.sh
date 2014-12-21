#!/bin/bash

# Base functions for all unit-tests

TEST_BASE_DIR="$(pwd)"
TEST_EXECUTION_DIR="${TEST_BASE_DIR}/execute"

# Import util functions
. ../lock-util.sh

# Set if log info is set
LOG_LEVEL_QUIET=0
LOG_LEVEL_ERROR=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3
logLevel=$LOG_LEVEL_QUIET

param="${1:-}"
if [ "$param" = "--debug" ]; then
	logLevel=$LOG_LEVEL_DEBUG
fi

# Get the log device
perlAvailable=$(perl -v)
if [ "$?" = 0 ]; then
	ttyDevice=$(perl -e 'use POSIX qw(ttyname); print POSIX::ttyname(2);')
elif [ -e "/dev/tty" ]; then
	ttyDevice="/dev/tty"
else
	ttyDevice="$(pwd)/git-lock-unitest.log"
fi

# Function to log messages to the right device
logMessage() {
	echo "$1" > $ttyDevice
}

checkExpectedMsg() {
	checkParameter 2 "checkExpectedMsg() [EXPECTED_MSG] [RECEIVED_MSG]" "$@"
	expectedMsg="$1"; receivedMsg="$2";
	if [ "$receivedMsg" = "${receivedMsg/$expectedMsg/}" ]; then
		fail "Expected another string in the error msg (expected=$expectedMsg, received=$receivedMsg)"
	fi
}

saveTestResults() {
	saveTestResult "tests passed" "${__shunit_testsPassed}"
	saveTestResult "tests failed" "${__shunit_testsFailed}"
	saveTestResult "tests total" "${__shunit_testsTotal}"
	saveTestResult "duration" "${__shunit_duration}"
}

saveTestResult() {
	local property="$1"; local newValue="$2";
	testResultsFile="${TEST_BASE_DIR}/testResultsFile.out"
	readProperty oldValue "$testResultsFile" "$property"
	if [ $? -ne 0 ]; then
		writeProperty "$testResultsFile" "$property" "$newValue"
	else
		writeProperty "$testResultsFile" "$property" "$(($oldValue+$newValue))"
	fi
}
