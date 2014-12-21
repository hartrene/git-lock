#!/bin/bash

# Unit-tests for the git-lock client functionality.
# The unit tests get executed by shunit (see end of this script)

# Run the client-test setup
. ./client-test-base.sh "$@" 

testClientShouldBeAbleToInit() {
	initProject
	checkAllRequiredPropertiesAreSetup
}

testClientShouldSetupProjectAndReleaseOnInit() {
	initProject
	returnValue=$(lockClient lookup-project-dir "$TEST_PROJECT")
	assertEquals "Server should confirm the setup of the new project after init: $returnValue" 0 $?
	returnValue=$(lockClient lookup-release-dir "$TEST_PROJECT" "$TEST_RELEASE")
	assertEquals "Server should confirm the setup of the new project+release after init: $returnValue" 0 $?
}

testClientShouldComplainThatProjectAndReleaseWasntSetupWithoutRunningInit() {
	returnValue=$(lockClient lookup-project-dir "$TEST_PROJECT")
	assertEquals "Server should complain that project wan't setup without running init first: $returnValue" 1 $?
	checkExpectedMsg "not found" "$returnValue"
	returnValue=$(lockClient lookup-release-dir "$TEST_PROJECT" "$TEST_RELEASE")
	assertEquals "Server should complain that project+release wan't setup without running init first: $returnValue" 1 $?
	checkExpectedMsg "not found" "$returnValue"
}

testClientShouldBeAbleToSetPropertiesOnEmptyProject() {
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	returnValue=$(lockClient set-property -p "$TEST_PROJECT" -r "$TEST_RELEASE" -remote-user "$TEST_REMOTE_USER" -server "$TEST_SERVER_ADDRESS" -ssh-port "$TEST_SERVER_SSH_PORT")
	assertEquals "set-property should run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToSwitchProperties() {
	initProject
	returnValue=$(lockClient switch-remote-user "new remote user")
	assertEquals "switch-project should run successfully: $returnValue" 0 $?
	checkProperty "REMOTE_USER" "new remote user"
	returnValue=$(lockClient switch-server "new server")
	assertEquals "switch-project should run successfully: $returnValue" 0 $?
	checkProperty "SERVER_ADDRESS" "new server"
	returnValue=$(lockClient switch-ssh-port "new ssh port")
	assertEquals "switch-project should run successfully: $returnValue" 0 $?
	checkProperty "SSH_PORT" "new ssh port"
}

testClientShouldComplainThatItsNotAGitRepo() {
	# Switch to a directory which is not a git repository
	cd /
	returnValue=$(lockClient init 2>/dev/null)
	assertEquals "lockClient should complain that it wasn't called from a git repo directory: $returnValue" 1 $?
	checkExpectedMsg "Git root couldn't be found" "$returnValue"
}

testClientShouldBeAbleToCreateAProject() {
	initProject
	returnValue=$(lockClient create-project)
	assertEquals "Init should have run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToInitFromSubdirectory() {
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	mkdir "mySubdirectory"
	cd "mySubdirectory"
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete successfull: $returnValue" 0 $?
	checkAllRequiredPropertiesAreSetup
}

testClientShouldBeAbleToCreateWithProjectAndReleaseProperties() {
	# Set-up git
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	# Set necessary properties first
	returnValue=$(lockClient set-property -remote-user "$TEST_REMOTE_USER" -server "$TEST_SERVER_ADDRESS" -ssh-port "$TEST_SERVER_SSH_PORT")
	assertEquals "set-property should run successfully: $returnValue" 0 $?
	# Run init with project and release property
	returnValue=$(lockClient create-project -p "$TEST_PROJECT" -r "$TEST_RELEASE")
	assertEquals "Init should have run successfully with project and release property: $returnValue" 0 $?
}

testClientShouldBeAbleToPrintTheGitLockProperties() {
	initProject
	returnValue=$(lockClient properties)
	assertEquals "properties lookup should run successfully: $returnValue" 0 $?
	checkExpectedMsg "REMOTE_USER" "$returnValue"
	checkExpectedMsg "SERVER_ADDRESS" "$returnValue"
	checkExpectedMsg "SERVER_SSH_PORT" "$returnValue"
	checkExpectedMsg "PROJECT" "$returnValue"
	checkExpectedMsg "RELEASE" "$returnValue"
}

testClientShouldBeAbleToLockAFile() {
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	# File should become writable after acquiring the lock
	if [ ! -w "$TEST_FILE" ]; then	
		fail "After locking a file it should be writable"
	fi
}

testClientShouldNotAllowToLockAFileTwiceWithoutUnlockFirst() {
	# Acquire lock for the first file
	lockFile "$TEST_FILE" "some binary data"
	# Acquire a second lock for the same file which is expected to fail
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Second lock for the same file should have produced a failure: $returnValue" 1 $?
	checkExpectedMsg "already locked" "$returnValue"
}

testClientShouldBeAbleToLockTwoFilesWithSameNameButDifferentDirectory() {
	initProject
	# Create first test file
	echo "some binary data" > "$TEST_FILE"
	# Create second test file with same name but in a different directory
	anotherDirectory="secondFileTestDir"
	mkdir "$anotherDirectory"
	echo "some binary data" > "$anotherDirectory/$TEST_FILE"
	# Acquire lock for the first file from server
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "First lock should have run successfully: $returnValue" 0 $?
	# Acquire a second lock for the same file in an other directory which should work
	cd "$anotherDirectory"
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Second lock for the same filename but in another directory should have worked: $returnValue" 0 $?
}

testClientShouldNotBeAbleToLockAFileWithoutInitFirst() {
	# Create test file
	echo "some binary data" > "$TEST_FILE"
	# Try to lock which should fail
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Should not be able to lock a file without init first: $returnValue" 1 $?
	checkExpectedMsg "Run 'git-lock init' first" "$returnValue"
}

testClientShouldBeAbleToUnlockALockedFile() {
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	# File should be readonly again
	if [ -w "$TEST_FILE" ]; then	
		fail "Client should have set the file to readonly after unlocking"
	fi
}

testClientShouldNotBeAbleToLockAnOldVersionOfAFile() {
	# Acquire lock from server
	testClientShouldBeAbleToUnlockALockedFile
	# Acquire lock from server again with an old file content hash
	chmod u+w "$TEST_FILE"
	lockFile "$TEST_FILE" "some binary data"
	# Change the file content
	echo "some other content" > "$TEST_FILE"
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	# Restore previous content of the file
	chmod u+w "$TEST_FILE"
	echo "some binary data" > "$TEST_FILE"
	# Acquire lock from server again
	lockResult=$(lockClient lock "$TEST_FILE")
	assertEquals "Lock of a file with old content should fail: $lockResult" 1 $?
	# Validate that the error msg contains a user who changed the file and a timestamp when it was done
	checkExpectedMsg "already modified by $GIT_USER at" "$lockResult"
}

testClientShouldBeAbleToShowTheAvailableProjectsAndReleasesOnTheServer() {
	initProject
	returnValue=$(lockClient lookup-projects)
	assertEquals "Error while trying to loopkup-server-projects: $returnValue" 0 $?
	checkExpectedMsg "$TEST_PROJECT" "$returnValue"
	checkExpectedMsg "$TEST_RELEASE" "$returnValue"
}

testClientShouldBeAbleToCancelALock() {
	lockFile "$TEST_FILE" "some binary data"
	returnValue=$(lockClient cancel "$TEST_FILE")
	assertEquals "Should be able to cancel a lock: $returnValue" 0 $?
}

testClientShouldMakeAFileReadonlyAfterCancel() {
	testClientShouldBeAbleToCancelALock
	if [ -w "${TEST_FILE}" ]; then
		fail "After cancel the file should be readonly"
	fi
}

testClientShouldFailIfSameFileLockTwiceInDifferentRepositories() {
	mkdir repo1; cd repo1; initProject;
	# Create test file
	echo "some binary data" > "$TEST_FILE"
	# Acquire lock from server
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "First lock should have run successfully: $returnValue" 0 $?
	# Swtich to another repo
	cd ..; mkdir repo2; cd repo2;
	initProject
	# Create test file
	echo "some binary data" > "$TEST_FILE"
	# Acquire lock from server
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Second lock should have failed: $returnValue" 1 $?
	checkExpectedMsg "File is already locked" "$returnValue"
}

testClientShouldShowProjectAndRelease() {
	initProject
	returnValue=$(lockClient status)
	assertEquals "Should be able to show the status: $returnValue" 0 $?
	checkExpectedMsg "$TEST_PROJECT" "$returnValue"
	checkExpectedMsg "$TEST_RELEASE" "$returnValue"
}

testClientShouldShowUsersLocks() {
	initProject
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	# Acquire another lock in a sub directory
	mkdir "$TEST_FILE_2_DIR"
	lockFile "$TEST_FILE_2" "some binary data"
	# Get users locks
	returnValue=$(lockClient status)
	assertEquals "Should be able to show the users locks: $returnValue" 0 $?
	checkExpectedMsg "$TEST_FILE" "$returnValue"
	checkExpectedMsg "$TEST_FILE_2" "$returnValue"
}

testClientShouldPrintMessageIfUserHasNoLocks() {
	initProject
	returnValue=$(lockClient status)
	assertEquals "Should be able to show the users locks: $returnValue" 0 $?
	checkExpectedMsg "User has no locks" "$returnValue"
}

testClientShouldBeAbleToSwitchTheProject() {
	initProject
	returnValue=$(lockClient switch-project "ANOTHER PROJECT" "ANOTHER RELEASE")
	assertEquals "Should be able to switch the project: $returnValue" 0 $?
}

testClientShouldFailToSwitchTheProjectIfUserStillHasFilesLocked() {
	initProject
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	# Switch the project
	returnValue=$(lockClient switch-project "ANOTHER PROJECT" "ANOTHER RELEASE")
	assertEquals "Should not be able to switch the project: $returnValue" 1 $?
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	# Now switching the project should pass
	returnValue=$(lockClient switch-project "ANOTHER PROJECT" "ANOTHER RELEASE")
	assertEquals "Should be able to switch the project: $returnValue" 0 $?
}

testClientShouldShowLocksOfAllUsers() {
	mkdir repo1; cd repo1; initProject;
	# Create test file
	echo "some binary data" > "$TEST_FILE"
	# Acquire lock from server
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Lock should have run successfully: $returnValue" 0 $?
	# Swtich to another repo
	cd ..; mkdir repo2; cd repo2
	initProject
	git config user.name "$ANOTHER_GIT_USER"
	# Create test file
	mkdir "$TEST_FILE_2_DIR"
	echo "some binary data" > "$TEST_FILE_2"
	# Acquire lock from server
	returnValue=$(lockClient lock "$TEST_FILE_2")
	assertEquals "Lock should have run successfully: $returnValue" 0 $?
	# Get user locks
	returnValue=$(lockClient all-locks)
	assertEquals "All-locks should have run successfully: $returnValue" 0 $?
	checkExpectedMsg "$GIT_USER" "$returnValue"
	checkExpectedMsg "$TEST_FILE" "$returnValue"
	checkExpectedMsg "$ANOTHER_GIT_USER" "$returnValue"
	checkExpectedMsg "$TEST_FILE_2" "$returnValue"
}

testClientShouldIndicateThatNoUserHasLocks() {
	initProject
	returnValue=$(lockClient all-locks)
	assertEquals "All-locks should have run successfully: $returnValue" 0 $?
	checkExpectedMsg "No locks found" "$returnValue"
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null
