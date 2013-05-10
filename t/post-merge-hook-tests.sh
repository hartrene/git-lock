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
POST_MERGE_HOOK="${LOCK_HOOK_DIRECTORY}/post-merge"

# Redirect the lock-server call, because some tests resetting LOCK_SERVER_DIR to simulate a hook run not on a lock-server
LOCK_SERVER_SSH_COMMAND="$(pwd)/lock-server-unittest-call-setup.sh"
if [ $logLevel -eq $LOG_LEVEL_QUIET ]; then
	LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND --quiet"
fi
export LOCK_SERVER_SSH_COMMAND="$LOCK_SERVER_SSH_COMMAND"

initGitRepositories() {
	# Create new working repository
	# In this repository we do our changes
	mkdir working-repo
	cd working-repo
	returnValue=$(git init)
	cd ..
	
	# Clone the working repo to a merge repo
	returnValue=$(git clone working-repo merge-repo 2>/dev/null)
	# Copy the post-commit hook into the merge-repo
	cp "$POST_MERGE_HOOK" merge-repo/.git/hooks
	
	# Init git-lock and checkint everything so that the master branch gets created
	cd merge-repo
	initGitLock
	git add . &> /dev/null
	git commit -m "Added git-lock properties file" &> /dev/null
	cd ..
	
	# Do all changes in the working-repo
	cd working-repo
	
	# Init git lock
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete sucessfull: $returnValue" 0 $?
}

callHook() {
	# Commit the changes to the working-repo
	returnValue=$(git commit -m 'Committing changes')
	assertEquals "Git commit should run successfully: $returnValue" 0 $?
	
	# Fetch the changes from the working-repo to the merge-repo and merge the changes, which will trigger the post-merge hook
	cd ../merge-repo
	logDebug "Fetch changes from the working-repo"
	returnValue=$(git fetch origin &> git-fetch.log)
	
	logDebug "Merge changes from the working-repo, which will trigger the post-merge hook"
	returnValue=$(git merge origin/master &> git-merge.log)
	returnCode=$?
	
	# Store all git log messages
	returnValue=$(cat git-merge.log)
	logDebug "$returnValue"
	
	# Change back to the working-dir
	cd ../working-repo
	
	echo "$returnValue"
	return $returnCode
}

testPostMergeHookHookShouldFailIfALockedFileWasAddedToCommit() {
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
	checkExpectedMsg "locked file '$TEST_FILE'" "$returnValue"
}

testPostMergeHookHookShouldAllowToCommitAnUnlockedFile() {
	initGitRepositories
	lockFile "$TEST_FILE" "adf23"
	
	# Stage the changed file
	returnValue=$(git add "$TEST_FILE")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Stage the unlock-confirmation file
	returnValue=$(git add ".${TEST_FILE}.lock-change-confirm")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	checkExpectedMsg "post-merge hook successfully verified all merge changes" "$returnValue"
}

testPostMergeHookHookShouldFailIfTheRemoveConfirmationWasntAdded() {
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
	checkExpectedMsg "${TEST_FILE}.lock-remove-confirm' wasn't added to commit" "$returnValue"
}

testPostMergeHookHookShouldAllowToCommitARemovedFile() {
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
	
	# Stage the removal of the file
	returnValue=$(git rm "$TEST_FILE")
	assertEquals "Git rm should run successfully: $returnValue" 0 $?
	
	# Stage the remove confirmation file as well
	returnValue=$(git add ".${TEST_FILE}.lock-remove-confirm")
	assertEquals "Git add should have run successfully: $returnValue" 0 $?;
	
	# Run the hook
	returnValue=$(callHook)
	checkExpectedMsg "post-merge hook successfully verified all merge changes" "$returnValue"
}

testPostMergeHookHookShoulFailIfRemoveSignatureWasCommittedButFileWasNotRemovedInCommit() {
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
	checkExpectedMsg "'$TEST_FILE' was not committed" "$returnValue"
}

testPostMergeHookHookShoulFailIfLockChangeConfirmSignatureWasCommittedButFileWasNotAddedInTheCommit() {
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
	checkExpectedMsg "'$TEST_FILE' was not committed" "$returnValue"
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null