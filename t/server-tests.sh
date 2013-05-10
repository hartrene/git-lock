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

# Unit-tests for the lock-server functionality.
# The unit tests get executed by shunit (see end of this script)

# Import test util functions
. ./unit-test-util.sh "$@"

# Set the global test and server directory
LOCK_SERVER_BIN_DIR="$(pwd)/../"
LOCK_SERVER_DIR="${TEST_EXECUTION_DIR}/server-test"

# Import util functions
. ../lock-util.sh

# Import the server functionality
. ../lock-server-lib.sh

TEST_USER_NAME="Test User"
TEST_PROJECT_NAME="My Project"
TEST_RELEASE_NAME="1 3"
TEST_FILENAME_HASH="23423423o4iu"
TEST_FILE_CONTENT_HASH="1st-file-content-hash"
TEST_SECOND_FILE_CONTENT_HASH="2nd-file-content-hash"
TEST_THIRD_FILE_CONTENT_HASH="3rd-file-content-hash"
TEST_LOCK_CONTENT_FILE_PATH="${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}/${TEST_FILENAME_HASH}.lock"
TEST_LOCK_INFO_FILE_PATH="${TEST_LOCK_CONTENT_FILE_PATH}info"
SOME_RANDOM_BASE64_SIGNATURE="cmFuZG9tCg=="
LOCK_SERVER_MUTEX="${LOCK_SERVER_DIR}/.mutex"

# Run before each test
setUp() {
	# Delete test dir before each test
	if [ -d "$TEST_EXECUTION_DIR" ]; then
		rm -r "$TEST_EXECUTION_DIR"
	fi
}

# Run once after all tests are run
oneTimeTearDown() {
	if [ -d "$TEST_EXECUTION_DIR" ]; then
		rm -r "$TEST_EXECUTION_DIR"
	fi
}

testServerShouldComplainIfGlobalWorkingDirDoesntExists() {
	serverDir="$LOCK_SERVER_DIR"
	LOCK_SERVER_DIR=
	
	returnValue=$(lockServer init "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "lockServer init should complain if global working directory doesn't exists: $returnValue" 1 $?
	checkExpectedMsg "LOCK_SERVER_DIR not found" "$returnValue"
	
	LOCK_SERVER_DIR="$serverDir"
}

testServerShouldBeAbleToCreateNewReleaseFolder() {
	returnValue=$(lockServer init "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after init: $returnValue" 0 $?
	
	if [ ! -d "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}" ]; then
		fail "Server should create project directory during init"
	fi
	
	if [ ! -d "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}" ]; then
		fail "Server should create release directory during init"
	fi
}

testServerShouldRunIfProjectAndReleaseWasSuccessfullySetup() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	returnValue=$(lockServer lookup-project-dir "$TEST_PROJECT_NAME")
	assertEquals "Server should return 0 (success) after the project was setup: $returnValue" 0 $?
	
	returnValue=$(lockServer lookup-release-dir "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after the project+release was setup: $returnValue" 0 $?
}

testServerShouldFailIfProjectAndReleaseWasntSetup() {
	returnValue=$(lockServer lookup-project-dir "$TEST_PROJECT_NAME")
	assertEquals "Server should return 1 (failure) because project wasn't setup: $returnValue" 1 $?
	checkExpectedMsg "not found" "$returnValue"
	
	returnValue=$(lockServer lookup-release-dir "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 1 (failure) because project+release wasn't found: $returnValue" 1 $?
	checkExpectedMsg "not found" "$returnValue"
}

testServerShouldDeleteMutexFolderAfterExitTheServerProgramWithError() {
	returnValue=$(lockServer init)
	assertEquals "Server should return 1 (failure) if parameters are missing" 1 $?
	checkExpectedMsg "Unexpected parameter" "$returnValue"
	
	if [ -d "$LOCK_SERVER_MUTEX" ]; then
		fail "Mutex directory must be deleted after the server returns from an wrong function call: $returnValue"
	fi
}

testServerShouldComplainIfAnotherScriptIsAlreadyRunning() {
	returnValue=$(acquireMutex "$LOCK_SERVER_MUTEX" 1 20)
	assertEquals "Acquisition of the mutex failed?" 0 $?
	
	returnValue=$(lockServer init "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 1 (failure) if another script is already running" 1 $?
	checkExpectedMsg "already running" "$returnValue"
	
	returnValue=$(releaseMutex "$LOCK_SERVER_MUTEX")
	assertEquals "Release of the mutex failed?" 0 $?
}

testServerShouldBreakMutexIfItIsHoldToLong() {
	returnValue=$(acquireMutex "$LOCK_SERVER_MUTEX" 1 20)
	assertEquals "Acquisition of the mutex failed?" 0 $?
	
	# fake the mutex acquired time to some long in the past
	touch -d "25 Dec 1980 10:05" "${LOCK_SERVER_MUTEX}"
	
	returnValue=$(lockServer init "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) if another process got the mutex a long time in the past" 0 $?	
}

testServerShouldBeAbleToHandleExistingServerDir() {
	createDir "${LOCK_SERVER_DIR}" "" "Failed to create test directory: ${LOCK_SERVER_DIR}"
	testServerShouldBeAbleToCreateNewReleaseFolder
}

testServerShouldBeAbleToHandleExistingProject() {
	createDir "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}" "" "Failed to create test directory: ${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}"
	testServerShouldBeAbleToCreateNewReleaseFolder
}

testServerShouldBeAbleToHandleExistingReleaseDir() {
	createDir "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}" "" "Failed to create test directory: ${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}"
	testServerShouldBeAbleToCreateNewReleaseFolder
}

testServerShouldCreateKeysWhenInitProject() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	if [ ! -f "$LOCK_SERVER_PRIVATE_KEY_FILE" ]; then
		fail "Server should create private key during init"
	fi
	
	if [ ! -f "$LOCK_SERVER_PUBLIC_KEY_FILE" ]; then
		fail "Server should create public key during init"
	fi
}

testServerShouldNotCreateNewKeysIfServerDirAlreadyExists() {
	createDir "$LOCK_SERVER_KEYS_DIR" "" "Failed to create test directory: $LOCK_SERVER_KEYS_DIR"
		
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	# Check that the server didn't try to create a new private key, because the project was already there, so it should try to recreate the keys
	if [ -f "$LOCK_SERVER_PRIVATE_KEY_FILE" ]; then
		fail "Server should not re-create the keys if the project was already there"
	fi
}

testServerShouldBeAbleToAddANewFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	changeConfirmationSignature=$(lockServer add "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH")
	assertEquals "Server should return 0 (success) after adding a file: $changeConfirmationSignature" 0 $?
	echo "$changeConfirmationSignature"
}

testServerShouldReturnFailureInCaseFileWasAlreadyAdded() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	changeConfirmationSignature=$(lockServer add "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH")
	assertEquals "First add should be successful" 0 $?
	changeConfirmationSignature=$(lockServer add "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH")
	assertEquals "Server should return 1 (error) after adding an already added file: $changeConfirmationSignature" 1 $?
	checkExpectedMsg "already modified" "$changeConfirmationSignature"
	checkExpectedMsg "user" "$changeConfirmationSignature"
	checkExpectedMsg "timestamp" "$changeConfirmationSignature"
}

testServerShouldReturnTheChangeConfirmationSignatureAfterAdding() {
	changeConfirmationSignature=$(testServerShouldBeAbleToAddANewFile)
	
	test -n "$changeConfirmationSignature"
	assertEquals "Server should return the change confirmation signature after adding" 0 $?
}

testServerShouldBeAbleToValidateTheReceivedChangeConfirmationSignatureAfterAdding() {
	changeConfirmationSignatureBase64=$(testServerShouldBeAbleToAddANewFile)
	publicKeyFile=$(receiveAndStoreServersPublicKey "${TEST_EXECUTION_DIR}/.public_key")
	verifySignature "$publicKeyFile" "$changeConfirmationSignatureBase64" "$TEST_FILE_CONTENT_HASH"
	
	assertEquals "Should be able to verify the signature with servers public key. Received change confirmation signature: $changeConfirmationSignatureBase64" 0 $?
}

testServerShouldReturnSuccessAfterLockingFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH")
	assertEquals "Server should return 0 (success) after locking an unlocked file: $lockSignature" 0 $?
	echo "$lockSignature"
}

testServerShouldReturnFailureInCaseFileIsAlreadyLocked() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH")
	assertEquals "First lock should be successful" 0 $?
	lockSignature=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH")
	assertEquals "Server should return 1 (error) after locking an already locked file: $lockSignature" 1 $?
	checkExpectedMsg "is locked" "$lockSignature"
	checkExpectedMsg "user" "$lockSignature"
	checkExpectedMsg "timestamp" "$lockSignature"
}

testServerShouldComplainThatInitWasNotRunningWhenLockingFile() {
	lockSignature=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH")
	assertFalse "Server should complain that init was not running when trying to lock a file: $lockSignature" $?
}

testServerShouldCreateLockFilesWhenLockingFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	test -s "$TEST_LOCK_CONTENT_FILE_PATH"
	assertEquals "Server should have created a non-zero lock file" 0 $?
	
	test -s "$TEST_LOCK_INFO_FILE_PATH"
	assertEquals "Server should have created a non-zero lock info file" 0 $?
}

testServerShouldDeleteTheLockSignatureAfterLocking() {
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	if [ -e "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}/${TEST_FILENAME_HASH}.lsig" ]; then
		fail "After creating a lock it should delete the temporarily created lock signature"
	fi
}

testServerShouldStoreUsernameTimestampInLockInfoFileAfterLocking() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	grep -q "user:" "$TEST_LOCK_INFO_FILE_PATH"
	assertEquals "Lock info file should contain the username" 0 $?
	
	grep -q "timestamp:" "$TEST_LOCK_INFO_FILE_PATH"
	assertEquals "Lock info file should contain the timestamp" 0 $?
}

testServerShouldReturnTheLockSignatureAfterLocking() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	test -n "$lockSignature"
	assertEquals "Server should return the lock signature after locking" 0 $?
}

testServerShouldBeAbleToReturnThePublicKey() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	pubkey_returnValue="$(receiveServersPublicKey)"
	assertEquals "Server should end successfully when requested the public key: $pubkey_returnValue" 0 $?	
	
	test -n "$pubkey_returnValue"
	assertEquals "Server should be able to return the public key" 0 $?
}

testServerShouldComplainIfWrongLockSignatureWasSend() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	changeConfirmationSignature=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH" "d3JvbmcgdW5sb2NrIGNvZGUK")
	assertEquals "lockServer unlock should complain if wrong lock signature was send" 1 $?
	checkExpectedMsg "lock signature" "$changeConfirmationSignature"
}

testServerShouldBeAbleToUnlockAFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	changeConfirmationSignature=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH" "$lockSignature")
	assertEquals "lockServer unlock should run successfully" 0 $?
	
	echo "$changeConfirmationSignature"
}

testServerShouldBeAbleToValidateTheNewContentHashWithTheReceivedChangeConfirmationSignature() {
	changeConfirmationSignatureBase64=$(testServerShouldBeAbleToUnlockAFile)
	publicKeyFile=$(receiveAndStoreServersPublicKey "${TEST_EXECUTION_DIR}/.public_key")
	
	verifySignature "$publicKeyFile" "$changeConfirmationSignatureBase64" "$TEST_SECOND_FILE_CONTENT_HASH"
	assertEquals "Should be able to verify the received signature successfull with servers public key. Received change confirmation signature: $changeConfirmationSignatureBase64" 0 $?
}

testServerShouldDeleteTheChangeConfirmationSignatureAfterUnlocking() {
	changeConfirmationSignature=$(testServerShouldBeAbleToUnlockAFile)
	
	if [ -e "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}/${TEST_FILENAME_HASH}.ccsig" ]; then
		fail "After unlocking a file the server should delete the temporarily created change confirmation signature"
	fi
}

testServerShouldNotBeAbleToLockAnOldVersion() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	# Try to lock twice with the same content
	oldChangeConfirmationSignatureBase64=$(testServerShouldBeAbleToUnlockAFile)
	
	# Lock and unlock the file once more (both should pass)
	lockSignature=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$oldChangeConfirmationSignatureBase64")
	assertEquals "lockServer lock should be able to lock a file with the corrent change confirmation signature" 0 $?
	changeConfirmationSignature=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_THIRD_FILE_CONTENT_HASH" "$lockSignature")
	assertEquals "lockServer unlock should run successfully" 0 $?
	
	# Using the old change confirmation signature to lock the file should fail
	lockReturnValue=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$oldChangeConfirmationSignatureBase64")
	assertEquals "lockServer lock should complain that this file was already edited by someone else: $lockReturnValue" 1 $?
	
	# Validate that the error msg contains a user who changed the file and a timestamp when it was done
	checkExpectedMsg "already modified" "$lockReturnValue"
	checkExpectedMsg "user" "$lockReturnValue"
	checkExpectedMsg "timestamp" "$lockReturnValue"
}

testServerShouldBeAbleToCancelALock() {
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	returnValue=$(lockServer cancel "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$lockSignature")
	assertEquals "lockServer cancel should run successfully" 0 $?
}

testServerShouldComplainIfWrongLockSignatureWasSendOnCancel() {
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	returnValue=$(lockServer cancel "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$SOME_RANDOM_BASE64_SIGNATURE")
	assertEquals "lockServer cancel should complain if wrong lock signature was send" 1 $?
	checkExpectedMsg "received lock signature failed" "$returnValue"
}

testServerShouldAllowToLockPreviousCancelledLockAgain() {
	testServerShouldBeAbleToCancelALock
	testServerShouldReturnSuccessAfterLockingFile
}

testServerShouldNotAllowToUnlockANeverLockedFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	returnValue=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH" "$SOME_RANDOM_BASE64_SIGNATURE")
	assertEquals "lockServer unlock should fail if file was never locked" 1 $?
	checkExpectedMsg "not locked" "$returnValue"
}

testServerShouldNotAllowToCancelANeverLockedFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	returnValue=$(lockServer cancel "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$SOME_RANDOM_BASE64_SIGNATURE")
	assertEquals "lockServer cancel should fail if file was never locked" 1 $?
	checkExpectedMsg "not locked" "$returnValue"
}

testServerShouldBeAbleToBanANewFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH")
	assertEquals "lockServer ban should run without any error: $banConfirmationSignature" 0 $?
}

testServerShouldBeAbleToBanAPreviousLockedFile() {
	changeConfirmationSignature=$(testServerShouldBeAbleToUnlockAFile)
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH" "$changeConfirmationSignature")
	assertEquals "lockServer ban should run without any error: $banConfirmationSignature" 0 $?
}

testServerShouldBeAbleToValidateTheReturnedBanConfirmationSignature() {
	changeConfirmationSignature=$(testServerShouldBeAbleToUnlockAFile)
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH" "$changeConfirmationSignature")
	assertEquals "lockServer ban should run without any error: $banConfirmationSignature" 0 $?
	
	publicKeyFile=$(receiveAndStoreServersPublicKey "${TEST_EXECUTION_DIR}/.public_key")
	verifySignature "$publicKeyFile" "$banConfirmationSignature" "${TEST_SECOND_FILE_CONTENT_HASH}-ban"
	assertEquals "Should be able to verify the signature with servers public key. Received ban confirmation confirmation signature: $banConfirmationSignature" 0 $?
}

testServerShouldNotAllowToBanALockedFile() {
	lockSignature=$(testServerShouldReturnSuccessAfterLockingFile)
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH")
	assertEquals "lockServer ban should fail if the file is locked: $banConfirmationSignature" 1 $?
	checkExpectedMsg "is locked" "$banConfirmationSignature"
}

testServerShouldNotAllowToBanAnOldVersion() {
	changeConfirmationSignature=$(testServerShouldBeAbleToUnlockAFile)
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH")
	assertEquals "lockServer ban should fail if an old version is going to be banned: $banConfirmationSignature" 1 $?
	checkExpectedMsg "modified" "$banConfirmationSignature"
	checkExpectedMsg "Get the latest version" "$banConfirmationSignature"
}

testServerShouldComplainIfAFileWasAlreadyBanned() {
	testServerShouldBeAbleToBanAPreviousLockedFile
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH")
	assertEquals "lockServer should fail if a file was already banned: $banConfirmationSignature" 1 $?
	checkExpectedMsg "already banned" "$banConfirmationSignature"
}

testServerShouldNotAllowToLockANeverLockedAndPreviouslyBannedFile() {
	testServerShouldBeAbleToBanANewFile
	
	lockReturnValue=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH")
	assertEquals "lockServer lock should not allow to lock an already banned file: $lockReturnValue" 1 $?
	checkExpectedMsg "banned" "$lockReturnValue"
}

testServerShouldNotAllowToLockAPreviouslyLockedAndPreviouslyBannedFile() {
	changeConfirmationSignature=$(testServerShouldBeAbleToUnlockAFile)
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH" "$changeConfirmationSignature")
	assertEquals "lockServer should allow to ban an unlocked file: $banConfirmationSignature" 0 $?
	
	lockReturnValue=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH")
	assertEquals "lockServer should not allow to lock a banned file: $lockReturnValue" 1 $?
	checkExpectedMsg "banned" "$lockReturnValue"
}

testServerShouldBeAbleToAddAPreviouslyBannedFile() {
	changeConfirmationSignature=$(testServerShouldBeAbleToUnlockAFile)
	
	banConfirmationSignature=$(lockServer ban "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_SECOND_FILE_CONTENT_HASH" "$changeConfirmationSignature")
	assertEquals "lockServer should allow to ban a unlocked file: $banConfirmationSignature" 0 $?
	
	returnValue=$(lockServer add "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH" "$banConfirmationSignature")
	assertEquals "lockServer should be able to add a previously banned file: $returnValue" 0 $?
	
	echo "$returnValue"
}

testServerShouldBeAbleToLockAnPreviouslyReallowedFile() {
	changeConfirmationSignature=$(testServerShouldBeAbleToAddAPreviouslyBannedFile)
	
	lockReturnValue=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$changeConfirmationSignature")
	assertEquals "lockServer should allow to lock a previously restored file: $lockReturnValue" 0 $?
}

testServerShouldNotBeAbleToAddABannedFileWithTheWrongBanConfirmationSignature() {
	testServerShouldBeAbleToBanANewFile
	
	returnValue=$(lockServer add "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILENAME_HASH" "$TEST_FILE_CONTENT_HASH" "$SOME_RANDOM_BASE64_SIGNATURE")
	assertEquals "lockServer should fail to add a banned file with the wrong ban-confirmation-signature: $returnValue" 1 $?
	checkExpectedMsg "Validation" "$returnValue"
	checkExpectedMsg "failed" "$returnValue"
}

testServerShouldDeleteTempBanConfSigAfterBanning() {
	testServerShouldBeAbleToBanAPreviousLockedFile
	
	if [ -e "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}/${TEST_FILENAME_HASH}.bcsig" ]; then
		fail "After banning a file the server should delete the temporarily created ban confirmation signature"
	fi
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null