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

# Unit-tests for the git pre-receive hook

# Run thie client-test setup
. ./client-test-base.sh "$@"

LOCK_HOOK_DIRECTORY="$(pwd)/../hooks"
PRE_RECEIVE_HOOK="${LOCK_HOOK_DIRECTORY}/pre-receive"

# Redirect the lock-server call, because some tests resetting LOCK_SERVER_DIR to simulate a hook run not on a lock-server
LOCK_SERVER_SSH_COMMAND="$(pwd)/lock-server-unittest-call-setup.sh"
if [ $logLevel -eq $LOG_LEVEL_QUIET ]; then
	LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND --quiet"
fi
export LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND"

# Add the git-lock script to the path to be able to simulate a run on a client
export PATH=$PATH:$(pwd)/..

initGitRepositories() {
	# Create new bare origin repository
	mkdir origin-repo
	cd origin-repo
	returnValue=$(git init --bare)
	cd ..
	
	# Copy the pre-receive hook to the origin repo
	cp "$PRE_RECEIVE_HOOK" origin-repo/hooks
	
	# Clone the origin repository
	returnValue=$(git clone origin-repo working-repo 2>/dev/null)
	cd working-repo
	
	# Init git lock
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete sucessfull: $returnValue" 0 $?
}

callHook() {
	# Commit the changes to the working-repo
	returnValue=$(git commit -m 'Committing changes')
	assertEquals "Git commit should run successfully: $returnValue" 0 $?
	
	# Push the changes to the origin to the trigger pre-receive hook
	logDebug "Push changes to origin, which will trigger the pre-receive hook"
	git push origin master &> git-push.log
	returnCode=$?
	
	# Store all git log messages
	returnValue=$(cat git-push.log)
	logDebug "$returnValue"
	
	echo "$returnValue"
	return $returnCode
}

testPreReceiveHookShouldFailIfALockedFileWasAddedToCommit() {
	initGitRepositories
	lockFile "$TEST_FILE" "adf23"
	
	# Stage the changed file
	returnValue=$(git add "$TEST_FILE")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Stage the lock file
	returnValue=$(git add ".${TEST_FILE}.lock")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should fail if a locked file was added to commit: $returnValue" 1 $?
	checkExpectedMsg "locked file '$TEST_FILE'" "$returnValue"
}

testPreReceiveHookShouldAllowToCommitAnUnlockedFile() {
	testPreReceiveHookShouldFailIfALockedFileWasAddedToCommit
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Unstage the lock file
	returnValue=$(git rm ".${TEST_FILE}.lock")
	assertEquals "Git rm should run successfully: $returnValue" 0 $?
	
	# Stage the unlock-confirmation file
	returnValue=$(git add ".${TEST_FILE}.lock-change-confirm")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should run ok if a file was unlocked and staged: $returnValue" 0 $?
}

testPreReceiveHookShouldAbleToPushInABareRepositoryWithoutHavingLockServerDirSetup() {
	initGitRepositories
	lockFile "$TEST_FILE" "adf23"
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Stage the changed file
	returnValue=$(git add "$TEST_FILE")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Stage the unlock-confirmation file
	returnValue=$(git add ".${TEST_FILE}.lock-change-confirm")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Commit the git-lock properties file, so that the hook is able to retrieve the lock-servers public-key
	returnValue=$(git add ".git-lock.properties")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Unset the LOCK_SERVER environment variable to simulate that the hook isn't running on the lock-server
	unset LOCK_SERVER_BIN_DIR
	unset LOCK_SERVER_DIR
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should run successfully if a locked file was added to commit: $returnValue" 0 $?
}

testPreReceiveHookShouldFailIfTheRemoveConfirmationWasntAdded() {
	initGitRepositories
	
	# Create a test file
	echo "01010101" > "$TEST_FILE"
	
	# Add that file from the lock-server
	returnValue=$(lockClient add "$TEST_FILE"); 
	assertEquals "Add should have run successfully: $returnValue" 0 $?;
	
	# Stage all changes
	returnValue=$(git add .)
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook to push all changes to origin
	returnValue=$(callHook)
	assertEquals "Hook should run successfully if a file was added: $returnValue" 0 $?
	
	# Delete the file
	returnValue=$(lockClient remove "$TEST_FILE");
	assertEquals "Remove should have run successfully: $returnValue" 0 $?;
	
	# Commit the removal of the file
	returnValue=$(git rm "$TEST_FILE")
	assertEquals "Git rm should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-receive hook should fail if the removed confirmation file wasn't added to commit: $returnValue" 1 $?
	checkExpectedMsg "${TEST_FILE}.lock-remove-confirm' wasn't added to commit" "$returnValue"
}

testPreReceiveHookShouldAllowToCommitARemovedFile() {
	testPreReceiveHookShouldFailIfTheRemoveConfirmationWasntAdded
	
	# Stage the remove confirmation file as well
	returnValue=$(git add ".${TEST_FILE}.lock-remove-confirm")
	assertEquals "Git add should have run successfully: $returnValue" 0 $?;
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-receive hook should run successfully if a removed file was added to commit: $returnValue" 0 $?
}

testPreReceiveHookShoulFailIfRemoveSignatureWasCommittedButFileWasNotRemovedInCommit() {
	initGitRepositories
	
	# Create a test file
	echo "01010101" > "$TEST_FILE"
	
	# Add that file from the lock-server
	returnValue=$(lockClient add "$TEST_FILE"); 
	assertEquals "Add should have run successfully: $returnValue" 0 $?;
	
	# Stage all changes
	returnValue=$(git add .)
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook to push all changes to origin
	returnValue=$(callHook)
	assertEquals "Hook should run successfully if a file was added: $returnValue" 0 $?
	
	# Remove that file from the lock-server
	returnValue=$(lockClient remove "$TEST_FILE"); 
	assertEquals "Remove should have run successfully: $returnValue" 0 $?;
	
	# Stage all changes
	returnValue=$(git add .)
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-receive hook should fail if the removed file wasn't removed in the commit, but the remove-confirmation signature was added" 1 $?
	checkExpectedMsg "'$TEST_FILE' was not committed" "$returnValue"
}

testPreReceiveHookShoulFailIfLockChangeConfirmSignatureWasCommittedButFileWasNotAddedInTheCommit() {
	initGitRepositories
	
	# Create a test file
	echo "01010101" > "$TEST_FILE"
	
	# Add that file from the lock-server
	returnValue=$(lockClient add "$TEST_FILE"); 
	assertEquals "Add should have run successfully: $returnValue" 0 $?;
	
	# Stage only the lock-confirm-signature
	returnValue=$(git add ".${TEST_FILE}.lock-change-confirm")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-receive hook should fail if the changed file wasn't added in the commit, but the lock-change-confirmation signature was added" 1 $?
	checkExpectedMsg "'$TEST_FILE' was not committed" "$returnValue"
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null