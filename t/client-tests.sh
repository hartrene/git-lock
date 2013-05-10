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

# Unit-tests for the git-lock client functionality.
# The unit tests get executed by shunit (see end of this script)

# Run the client-test setup
. ./client-test-base.sh "$@" 

testClientShouldBeAbleToInit() {
	initProject
	
	# Check that all required properties were setup
	checkAllRequiredProperties
}

testClientShouldSetupProjectAndReleaseOnInit() {
	initProject
	
	returnValue=$(lockClient lookup-project "$TEST_PROJECT_NAME")
	assertEquals "Server should confirm the setup of the new project after init: $returnValue" 0 $?
	
	returnValue=$(lockClient lookup-release "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should confirm the setup of the new project+release after init: $returnValue" 0 $?
}

testClientShouldComplainThatProjectAndReleaseWasntSetupWithoutRunningInit() {
	returnValue=$(lockClient lookup-project "$TEST_PROJECT_NAME")
	assertEquals "Server should complain that project wan't setup without running init first: $returnValue" 1 $?
	checkExpectedMsg "not found" "$returnValue"
	
	returnValue=$(lockClient lookup-release "$TEST_PROJECT_NAME" "$TEST_RELEASE_NAME")
	assertEquals "Server should complain that project+release wan't setup without running init first: $returnValue" 1 $?
	checkExpectedMsg "not found" "$returnValue"
}

testClientShouldBeAbleToSetPropertiesOnEmptyProject() {
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	
	# Set properties
	returnValue=$(lockClient set-property -p "$TEST_PROJECT_NAME" -r "$TEST_RELEASE_NAME" -remote-user "$TEST_REMOTE_USER" -server "$TEST_SERVER_ADDRESS" -ssh-port "$TEST_SERVER_SSH_PORT")
	assertEquals "set-property should run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToSwitchProperties() {
	initProject
	
	returnValue=$(lockClient switch-project "new project")
	assertEquals "switch-project should run successfully: $returnValue" 0 $?
	checkProperty "PROJECT" "new project"

	returnValue=$(lockClient switch-release "new release")
	assertEquals "switch-project should run successfully: $returnValue" 0 $?
	checkProperty "RELEASE" "new release"
	
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
	# Switch in to a directory which is not a git repository
	cd /
	
	returnValue=$(lockClient init 2>/dev/null)
	assertEquals "lockClient should complain that it wasn't called from a git repo directory: $returnValue" 1 $?
	checkExpectedMsg "Git root can't be found" "$returnValue"
}

testClientShouldBeAbleToInitTheServer() {
	initProject
	returnValue=$(lockClient init-project)
	assertEquals "Init should have run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToInitFromSubdirectory() {
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	
	mkdir "mySubdirectory"
	cd "mySubdirectory"
	
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete successfull: $returnValue" 0 $?
	
	checkAllRequiredProperties
}

testClientShouldBeAbleToInitTheServerWithProjectAndReleaseProperties() {
	# Set-up git
	git init > /dev/null
	assertEquals "Git init failed?" 0 $?
	
	# Set necessary properties first
	returnValue=$(lockClient set-property -remote-user "$TEST_REMOTE_USER" -server "$TEST_SERVER_ADDRESS" -ssh-port "$TEST_SERVER_SSH_PORT")
	assertEquals "set-property should run successfully: $returnValue" 0 $?
	
	# Run init with project and release property
	returnValue=$(lockClient init-project -p "$TEST_PROJECT_NAME" -r "$TEST_RELEASE_NAME")
	assertEquals "Init should have run successfully with project and release property: $returnValue" 0 $?
}

testClientShouldBeAbleToPrintTheGitLockContext() {
	initProject

	# Set necessary properties first
	returnValue=$(lockClient context)
	assertEquals "context should run successfully: $returnValue" 0 $?
	
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

testClientShouldStoreLockSignatureOnLock() {
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	
	# Check that the unlock code was saved
	if [ ! -f ".${TEST_FILE}.lock" ]; then
		fail "Client should save the lock signature after locking a file"
	fi
}

testClientShouldAddLockChangeConfirmFileOnLockWhenFileNotAddedYet() {
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	
	# Check that the lock-change-confirm was added after locking a new file
	if [ ! -f ".${TEST_FILE}.lock-change-confirm" ]; then
		fail "Client should add lock-change-confirm after locking a not added file"
	fi
}

testClientShouldBeAbleToAddAFileToBeLockable() {
	initProject
	
	# Create test file
	echo "testing the add functionality" > "$TEST_FILE"
	
	# Add file to be lockable
	returnValue=$(lockClient add "$TEST_FILE")
	assertEquals "Should be able to mark a file as lockable: $returnValue" 0 $?
	
	# Check that the lock-change-confirm was added after adding a new file
	if [ ! -f ".${TEST_FILE}.lock-change-confirm" ]; then
		fail "Client should add lock-change-confirm after locking a not added file"
	fi
	
	# File should be readonly
	if [ -w "$TEST_FILE" ]; then	
		fail "Client should have set the file to readonly after marking it as lockable"
	fi
}


testClientShouldNotBeAbleToAddAFileTwice() {
	initProject
	
	# Create test file
	echo "testing the add functionality" > "$TEST_FILE"

	# Add file to be lockable
	returnValue=$(lockClient add "$TEST_FILE")
	assertEquals "Should be able to mark a file as lockable: $returnValue" 0 $?
	
	# Add file to be lockable again
	returnValue=$(lockClient add "$TEST_FILE")
	assertEquals "Should not be able to add a file twice: $returnValue" 1 $?
}

testClientShouldBeAbleToUnlockALockedFile() {
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Check that the unlock code was removed
	if [ -f ".${TEST_FILE}.lock" ]; then
		fail "Client should have removed the lock signature after unlocking"
	fi
	
	# Check that the unlock confirmation was saved	
	if [ ! -f ".${TEST_FILE}.lock-change-confirm" ]; then
		fail "Client should have saved the change confirmation signature after unlocking"
	fi
	
	# File should be readonly again
	if [ -w "$TEST_FILE" ]; then	
		fail "Client should have set the file to readonly after unlocking"
	fi
}

testClientShouldDeleteUnlockDetailsFileAfterUnlocking() {
	testClientShouldBeAbleToUnlockALockedFile
	
	if [ -e ".${TEST_FILE}.lock-details" ]; then
		fail "After unlocking a file the client should delete the lock details file"
	fi
}

testClientShouldNotBeAbleToLockAnOldVersionOfAFile() {
	# Acquire lock from server
	testClientShouldBeAbleToUnlockALockedFile
	
	# Store the old change confirmation signature
	oldUnlockConfirmationSignature=$(cat ".${TEST_FILE}.lock-change-confirm")	
	
	# Acquire lock from server
	chmod u+w "$TEST_FILE"
	lockFile "$TEST_FILE" "some other binary data"
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Modify the stored change confirmation signature.
	#   This signature will be send to the server at the lock request 
	#   and should ensure that the client is making changes on behalf of the latest version.
	# Modifying this signature should stop the server from locking this file
	echo "$oldUnlockConfirmationSignature" > ".${TEST_FILE}.lock-change-confirm"
	
	# Acquire lock from server with an old change confirmation signature should fail
	lockReturnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Lock with an old change confirmation signature should fail: $lockReturnValue" 1 $?
	
	# Validate that the error msg contains a user who changed the file and a timestamp when it was done
	checkExpectedMsg "already modified" "$lockReturnValue"
	checkExpectedMsg "user" "$lockReturnValue"
	checkExpectedMsg "timestamp" "$lockReturnValue"
}

testClientShouldBeAbleToValidateTheChangeConfirmationSignature() {
	testClientShouldBeAbleToUnlockALockedFile
	
	# Get the hash of the test file content
	testFileContentHash=$(git hash-object "$TEST_FILE")
	assertEquals "Error while creating the file content hash occurred: $testFileContentHash" 0 $?
	
	# Get the change confirmation signature
	changeConfirmationFile=".${TEST_FILE}.lock-change-confirm"
	changeConfirmationBase64=$(cat "$changeConfirmationFile")
	
	# Get the pubkey from the server
	serverPubkeyFile="${LOCK_CLIENT_TEST_DIR}/.public_key"
	returnValue=$(lockClient lookup-server-pubkey "$serverPubkeyFile")
	assertEquals "Error while receiving the pubkey from the server occurred: $returnValue" 0 $?
	
	# Verify the signature
	verifySignature "$serverPubkeyFile" "$changeConfirmationBase64" "$testFileContentHash"
	assertEquals "Should be able to verify the received change confirmation against the content hash. Received change confirmation signature: $changeConfirmationBase64" 0 $?
}

testClientShouldBeAbleToShowTheAvailableProjectsAndReleasesOnTheServer() {
	initProject

	returnValue=$(lockClient lookup-projects)
	assertEquals "Error while trying to loopkup-server-projects: $returnValue" 0 $?
	
	checkExpectedMsg "$TEST_PROJECT_NAME" "$returnValue"
	checkExpectedMsg "$TEST_RELEASE_NAME" "$returnValue"
}

testClientShouldBeAbleToLockAFileSwitchTheProjectAndReleaseAndUnlockTheFile() {
	initProject
	
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	
	# Switch the project
	returnValue=$(lockClient switch-project "ANOTHER PROJECT")
	assertEquals "Should be able to switch the project: $returnValue" 0 $?
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToCancelALock() {
	# Acquire lock from server
	lockFile "$TEST_FILE" "some binary data"
	
	# Cancel the lock
	returnValue=$(lockClient cancel "$TEST_FILE")
	assertEquals "Should be able to cancel a lock: $returnValue" 0 $?
}

testClientShouldRemoveAllLockFilesOnCancel() {
	testClientShouldBeAbleToCancelALock
	
	if [ -e ".${TEST_FILE}.lock" ]; then
		fail "Cancel should remove the unlock file"
	fi
	
	if [ -e ".${TEST_FILE}.lock-details" ]; then
		fail "Cancel should remove the unlock-details file"
	fi
}

testClientShouldMakeAFileReadonlyAfterCancel() {
	testClientShouldBeAbleToCancelALock
	
	if [ -w "${TEST_FILE}" ]; then
		fail "After cancel the file should be readonly"
	fi
}

testClientShouldBeAbleToRemoveAFile() {
	testClientShouldBeAbleToUnlockALockedFile
	
	returnValue=$(lockClient remove "$TEST_FILE")
	assertEquals "Remove should have run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToAddAndLockAPreviouslyRemovedFile() {
	testClientShouldBeAbleToRemoveAFile
	
	returnValue=$(lockClient add "$TEST_FILE")
	assertEquals "Add should have run successfully: $returnValue" 0 $?
	
	testClientShouldBeAbleToUnlockALockedFile
}

testClientShouldBeAbleToRemoveAnAddedFile() {
	testClientShouldBeAbleToAddAFileToBeLockable
	
	returnValue=$(lockClient remove "$TEST_FILE")
	assertEquals "Remove should have run successfully: $returnValue" 0 $?
}

testClientShouldBeAbleToAddAndLockAPreviouslyRemovedNewFile() {
	testClientShouldBeAbleToRemoveAnAddedFile
	
	returnValue=$(lockClient add "$TEST_FILE")
	assertEquals "Add should have run successfully: $returnValue" 0 $?
	
	testClientShouldBeAbleToUnlockALockedFile
}

testClientShouldCleanupFilesystemAfterRemovingAFile() {
	testClientShouldBeAbleToRemoveAFile
	
	if [ -e ".${TEST_FILE}.lock-change-confirm" ]; then
		fail "Remove should delete the change-confirm file"
	fi
}

testClientShouldFailIfSameFileLockTwiceInDifferentRepositories() {
	mkdir repo1
	cd repo1
	initProject
	# Create test file
	echo "some binary data" > "$TEST_FILE"
	# Acquire lock from server
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "First lock should have run successfully: $returnValue" 0 $?
	
	cd ..
	mkdir repo2
	cd repo2
	initProject
	# Create test file
	echo "some binary data" > "$TEST_FILE"
	# Acquire lock from server
	returnValue=$(lockClient lock "$TEST_FILE")
	assertEquals "Second lock should have failed: $returnValue" 1 $?
	checkExpectedMsg "File is locked" "$returnValue"
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null