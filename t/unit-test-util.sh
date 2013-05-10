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
ttyDevice=$(perl -e 'use POSIX qw(ttyname); print POSIX::ttyname(2);')
if [ -z "$ttyDevice" ]; then
	ttyDevice="/dev/null"
fi

# Function to log messages to the right device
logMessage() {
	echo "$1" > $ttyDevice
}

receiveServersPublicKey() {
	checkParameter 0 "storeServersPublicKey()" "$@"
	
	pubkeyReturnValue=$(lockServer pubkey)
	expectSuccess "Server should end successfully when requested the public key: $pubkeyReturnValue" $?	
	
	test -n "$pubkeyReturnValue"
	expectSuccess "Server should be able to return the public key" $?
	
	echo "$pubkeyReturnValue"
}

receiveAndStoreServersPublicKey() {
	checkParameter 1 "storeServersPublicKey() [FILE_PATH_TO_STORE]" "$@"
	local fileToStore=$1
	
	receiveServersPublicKey > "$fileToStore"
	echo "$fileToStore"
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