#!/bin/bash

# Unit-tests of the lock-server functionality.
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
LOCK_SERVER_MUTEX="${LOCK_SERVER_DIR}/.mutex"
TEST_FILE="test.sh"
TEST_FILENAME_HASH="160affb407b94c2616b2ac1482d9a3ec"
TEST_FILE_CONTENT_HASH="1st-file-content-hash"
TEST_SECOND_FILE_CONTENT_HASH="2nd-file-content-hash"
TEST_THIRD_FILE_CONTENT_HASH="3rd-file-content-hash"
TEST_LOCK_FILE_PATH="${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}/$TEST_FILENAME_HASH.lock"

# Run before each test
setUp() {
	# Delete test dir before each test
	if [ -d "$TEST_EXECUTION_DIR" ]; then
		rm -r "$TEST_EXECUTION_DIR"
	fi
}

# Run once after all tests have been run
oneTimeTearDown() {
	if [ -d "$TEST_EXECUTION_DIR" ]; then
		rm -r "$TEST_EXECUTION_DIR"
	fi
}

testServerShouldComplainIfGlobalWorkingDirDoesntExists() {
	serverDir="$LOCK_SERVER_DIR"
	LOCK_SERVER_DIR=
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "lockServer init-project "master" should complain if global working directory doesn't exists: $returnValue" 1 $?
	checkExpectedMsg "LOCK_SERVER_DIR not found" "$returnValue"
	LOCK_SERVER_DIR="$serverDir"
}

testServerShouldBeAbleToCreateNewReleaseFolder() {
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	if [ ! -d "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}" ]; then
		fail "Server should create project directory during init"
	fi
	if [ ! -d "${LOCK_SERVER_DIR}/${TEST_PROJECT_NAME}/${TEST_RELEASE_NAME}" ]; then
		fail "Server should create release directory during init"
	fi
}

testServerShouldStoreBranchWithProjectRelease() {
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	branchDetails=$(cat "$LOCK_SERVER_BRANCH_DETAILS_FILE" | grep master)
	if [ "$branchDetails" != "master:$TEST_PROJECT_NAME/$TEST_RELEASE_NAME" ]; then
		assertEquals "Should store branch name and project/release in branchDetailsFile: $LOCK_SERVER_BRANCH_DETAILS_FILE but found: $branchDetails" 1 $?
	fi
}

testServerShouldSwitchBranchesProjectReleaseIfAlreadyExists() {
	returnValue=$(lockServer init-project "foo" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	returnValue=$(lockServer init-project "master" "Bla" "0.1")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	branchDetails=$(cat "$LOCK_SERVER_BRANCH_DETAILS_FILE" | grep master)
	if [ "$branchDetails" != "master:Bla/0.1" ]; then
		assertEquals "Should switch branches project/release in branchDetailsFile: $LOCK_SERVER_BRANCH_DETAILS_FILE but found: $branchDetails" 1 $?
	fi
}

testServerShouldNotRemoveOtherBranchDetailsWhenChangingBranchDetails() {
	returnValue=$(lockServer init-project "foo" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	returnValue=$(lockServer init-project "master" "Bla" "0.1")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	branchDetails=$(cat "$LOCK_SERVER_BRANCH_DETAILS_FILE" | grep foo)
	if [ "$branchDetails" != "foo:$TEST_PROJECT_NAME/$TEST_RELEASE_NAME" ]; then
		assertEquals "Should not touch other branch details when storing branch details: $LOCK_SERVER_BRANCH_DETAILS_FILE but found: $branchDetails" 1 $?
	fi
}

testServerShouldWorkIfProjectAndReleaseWasSuccessfullySetup() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	returnValue=$(lockServer lookup-project-dir "$TEST_PROJECT_NAME")
	assertEquals "Server should return 0 (success) after the project was setup: $returnValue" 0 $?
	returnValue=$(lockServer lookup-release-dir "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after the project+release was setup: $returnValue" 0 $?
}

testServerShouldDeleteMutexFolderAfterExitTheServerProgramWithError() {
	returnValue=$(lockServer init-project "master")
	assertEquals "Server should return 1 (failure) if parameters are missing" 1 $?
	checkExpectedMsg "Unexpected parameter" "$returnValue"
	if [ -d "$LOCK_SERVER_MUTEX" ]; then
		fail "Mutex directory must be deleted after the server returns from an wrong function call: $returnValue"
	fi
}

testServerShouldComplainIfAnotherScriptIsAlreadyRunning() {
	returnValue=$(acquireMutex "$LOCK_SERVER_MUTEX" 1 20)
	assertEquals "Acquisition of the mutex failed?" 0 $?
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
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
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
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

testServerShouldReturnSuccessAfterLockingFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "Server should return 0 (success) after locking an unlocked file: $lockResult" 0 $?
	echo "$lockResult"
}

testServerShouldReturnSuccessAfterLockingFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "Server should return 0 (success) after locking an unlocked file: $lockResult" 0 $?
	echo "$lockResult"
}

testServerShouldReturnFailureInCaseFileIsAlreadyLocked() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH"
	assertEquals "First lock should be successful" 0 $?
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "Server should return 1 (error) after locking an already locked file" 1 $?
	checkExpectedMsg "is already locked" "$lockResult"
	checkExpectedMsg "user" "$lockResult"
	checkExpectedMsg "timestamp" "$lockResult"
}

testServerShouldComplainThatInitWasNotRunningWhenLockingFile() {
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE"  "$TEST_FILE_CONTENT_HASH")
	assertFalse "Server should complain that init was not running when trying to lock a file: $lockResult" $?
}

testServerShouldStoreUsernameFilenmeTimestampInLockInfoFileAfterLocking() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockResult=$(testServerShouldReturnSuccessAfterLockingFile)
	grep -q "user:" "$TEST_LOCK_FILE_PATH"
	assertEquals "Lock info file should contain the username" 0 $?
	grep -q "file:$TEST_FILE" "$TEST_LOCK_FILE_PATH"
	assertEquals "Lock info file should contain the user" 0 $?
	grep -q "timestamp:" "$TEST_LOCK_FILE_PATH"
	assertEquals "Lock info file should contain the timestamp" 0 $?
}

testServerShouldBeAbleToUnlockAFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockResult=$(testServerShouldReturnSuccessAfterLockingFile)
	lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH"
	assertEquals "lockServer unlock should run successfully" 0 $?
}

testServerShouldNotUnlockANotLockedFile() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	unlockResult=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH")
	assertEquals "lockServer unlock should run successfully" 1 $?
	checkExpectedMsg "File is not locked" "$unlockResult"
}

testServerShouldNotBeAbleToLockAnOldVersion() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	# Try to lock with the same content twice
	testServerShouldBeAbleToUnlockAFile
	# Lock and unlock the file once more (both should pass)
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH")
	assertEquals "lockServer lock should be able to lock a file" 0 $?
	lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_THIRD_FILE_CONTENT_HASH"
	assertEquals "lockServer unlock should run successfully" 0 $?
	# Using an old content hash to lock the file should fail
	lockReturnValue=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH")
	assertEquals "lockServer lock should complain that this file was already edited by someone else: $lockReturnValue" 1 $?
	# Validate that the error msg contains a user who changed the file and a timestamp when it was done
	checkExpectedMsg "already modified" "$lockReturnValue"
	checkExpectedMsg "by $TEST_USER_NAME" "$lockReturnValue"
	checkExpectedMsg "at" "$lockReturnValue"
}

testServerVerifyChangesShouldSucceedIfNoFileIsLocked() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "Server should return 0 (success) after locking a file: $lockResult" 0 $?
	
	lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH"
	assertEquals "lockServer unlock should run successfully" 0 $?
	
	# Pretend change of a locked file	
	changedFiles=()
	changedFiles+=("master A $TEST_FILENAME_HASH $TEST_SECOND_FILE_CONTENT_HASH")
	changedFiles+=("master A OtherFileHash OtherContent")
	
	result=$(lockServer verify-changes "${changedFiles[@]}")
	assertEquals "Server should succeed if no files are locked: $result" 0 $?
}

testServerShouldComplainOnChangeVerificationIfUnknownBranchReceived() {
	# Init for another branch than the changed branch
	returnValue=$(lockServer init-project "master" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should return 0 (success) after create: $returnValue" 0 $?
	# Pretend change of files of an unknown branch
	changedFiles=()
	changedFiles+=("foo A $TEST_FILE $TEST_FILENAME_HASH $TEST_FILE_CONTENT_HASH")
	lockResult=$(lockServer verify-changes "${changedFiles[@]}")
	assertEquals "Server should fail change verification if unknown branch sent: $lockResult" 1 $?
}

testServerVerifyChangesShouldFailIfALockedFileWasAddedToCommit() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	lockResult=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "Server should return 0 (success) after locking a file: $lockResult" 0 $?
	
	# Pretend change of a locked file	
	changedFiles=()
	changedFiles+=("master A $TEST_FILENAME_HASH $TEST_FILE_CONTENT_HASH")
	changedFiles+=("master A OtherFileHash OtherContent")
	
	result=$(lockServer verify-changes "${changedFiles[@]}")
	assertEquals "Server should fail change verification if a changed file is locked: $result" 1 $?
	checkExpectedMsg "is locked" "$result"
	checkExpectedMsg "by $TEST_USER_NAME" "$result"
	checkExpectedMsg "at" "$result"
}

testServerVerifyChangesShouldPassIfAllFilesUnlocked() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	# Change the file
	echo "asdf" > "$TEST_FILE"
	assertEquals "Change of the test file should run successfully: $returnValue" 0 $?
	
	# Lock and unlock the file
	result=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "lockServer lock should run successfully: $result" 0 $?
	result=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH")
	assertEquals "lockServer unlock should run successfully: $result" 0 $?
	
	# Pretend change of a unlocked file	
	changedFiles=()
	changedFiles+=("master A $TEST_FILENAME_HASH $TEST_SECOND_FILE_CONTENT_HASH")
	
	result=$(lockServer verify-changes "${changedFiles[@]}")
	assertEquals "Server should pass change verification if file was unlocked: $result" 0 $?
}

testServerVerifyChangesShouldFailIfNotLatestVersionWasReceived() {
	testServerShouldBeAbleToCreateNewReleaseFolder
	
	# Change the file
	echo "asdf" > "$TEST_FILE"
	assertEquals "Change of the test file should run successfully: $returnValue" 0 $?
	
	# Lock and unlock the file
	result=$(lockServer lock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_FILE_CONTENT_HASH")
	assertEquals "lockServer lock should run successfully: $result" 0 $?
	result=$(lockServer unlock "$TEST_USER_NAME" "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME" "$TEST_FILE" "$TEST_SECOND_FILE_CONTENT_HASH")
	assertEquals "lockServer unlock should run successfully: $result" 0 $?
	
	# Pretend a change of an unlocked file and send an old content hash
	changedFiles=()
	changedFiles+=("master A $TEST_FILENAME_HASH $TEST_FILE_CONTENT_HASH")
	
	result=$(lockServer verify-changes "${changedFiles[@]}")
	assertEquals "Server should fail change verification if an old content hash was received: $result" 1 $?
	checkExpectedMsg "$TEST_FILE is not the latest version" "$result"
	checkExpectedMsg "from user $TEST_USER_NAME" "$result"
	checkExpectedMsg "at" "$result"
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null
