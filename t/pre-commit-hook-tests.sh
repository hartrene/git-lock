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

# Unit-tests for the git pre-commit hook

# Run client-test setup
. ./client-test-base.sh "$@"

LOCK_HOOK_DIRECTORY="$(pwd)/../hooks"
PRE_COMMIT_HOOK="${LOCK_HOOK_DIRECTORY}/pre-commit"

callHook() {
	logDebug "Call pre-commit hook"
	
	if [ $logLevel -ge $LOG_LEVEL_DEBUG ]; then
		returnValue=$("$PRE_COMMIT_HOOK" --debug "$@")
	else
		returnValue=$("$PRE_COMMIT_HOOK" --quiet "$@")	
	fi
	
	returnCode=$?
	echo "$returnValue"
	logDebug "$returnValue"
	
	return $returnCode
}

testPreCommitHookShouldRunOkIfCalledInAGitRepository() {
	initProject

	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should run ok if it was executed within a git repository: $returnValue" 0 $?
}

testPreCommitHookShouldFailIfHookIsNotCalledFromWithinAGitRepo() {
	# Switch in to a directory which is not a git repository
	cd /

	# Run the hook
	returnValue=$(callHook 2>/dev/null)
	assertEquals "pre-commit hook should fail if it was not executed within a git repository: $returnValue" 1 $?
	checkExpectedMsg "Git root can't be found" "$returnValue"
}

testPreCommitHookShouldFailIfALockedFileWasAddedToCommit() {
	initProject
	lockFile "$TEST_FILE" "adf23"
	
	# Stage the changed file
	returnValue=$(git add "$TEST_FILE")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should fail if a locked file was added to commit: $returnValue" 1 $?
	checkExpectedMsg "locked file '$TEST_FILE'" "$returnValue"
}

testPreCommitHookShouldAllowToCommitAnUnlockedFile() {
	testPreCommitHookShouldFailIfALockedFileWasAddedToCommit
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Stage the unlock-confirmation file
	returnValue=$(git add ".${TEST_FILE}.lock-change-confirm")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should run ok if a file was unlocked and staged: $returnValue" 0 $?
}

testPreCommitHookShouldFailIfTheChangeConfirmationWasNotStagedAfterUnlock() {
	testPreCommitHookShouldFailIfALockedFileWasAddedToCommit
	
	# Unlock the file
	returnValue=$(lockClient unlock "$TEST_FILE")
	assertEquals "Unlock should have run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should fail if the change confirmation signature was not staged: $returnValue" 1 $?
	checkExpectedMsg "'.${TEST_FILE}.lock-change-confirm' wasn't added" "$returnValue"
}

testPreCommitHookShouldFailIfTheChangeConfirmationWasNotStagedAfterAdd() {
	initProject
	
	# Create a test file
	echo "01010101" > "$TEST_FILE"
	
	# Add that file to the lock-server
	returnValue=$(lockClient add "$TEST_FILE"); 
	assertEquals "Add should have run successfully: $returnValue" 0 $?;
	
	# Stage the new file
	returnValue=$(git add "$TEST_FILE")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should fail if a new file was staged without the change-confirmation-signature: $returnValue" 1 $?
	checkExpectedMsg "${TEST_FILE}.lock-change-confirm' wasn't added to commit" "$returnValue"
}

testPreCommitHookShouldAllowToCommitAnAddedFile() {
	testPreCommitHookShouldFailIfTheChangeConfirmationWasNotStagedAfterAdd
	
	# Stage the change-confirmation-file
	returnValue=$(git add ".${TEST_FILE}.lock-change-confirm")
	assertEquals "Git add should have run successfully: $returnValue" 0 $?;
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should run successfully if a file was added to commit: $returnValue" 0 $?
}

testPreCommitHookShouldFailIfTheRemoveConfirmationWasntAddedToCommit() {
	initProject
	
	# Create a test file
	echo "01010101" > "$TEST_FILE"
	
	# Commit that file
	returnValue=$(git add "$TEST_FILE")
	returnValue=$(git commit -m "file added")
	assertEquals "git commit have run successfully: $returnValue" 0 $?
	
	# Add and remove that file from the lock-server
	returnValue=$(lockClient add "$TEST_FILE"); 
	assertEquals "Add should have run successfully: $returnValue" 0 $?;
	returnValue=$(lockClient remove "$TEST_FILE");
	assertEquals "Remove should have run successfully: $returnValue" 0 $?;
	
	# Stage the removal of the file
	returnValue=$(git rm "$TEST_FILE")
	assertEquals "Git rm should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should fail if the removed confirmation file wasn't added to commit: $returnValue" 1 $?
	checkExpectedMsg "${TEST_FILE}.lock-remove-confirm' wasn't added to commit" "$returnValue"
}

testPreCommitHookShouldAllowToCommitARemovedFile() {
	testPreCommitHookShouldFailIfTheRemoveConfirmationWasntAddedToCommit
	
	# Stage the remove confirmation file
	returnValue=$(git add ".${TEST_FILE}.lock-remove-confirm")
	assertEquals "Git add should have run successfully: $returnValue" 0 $?;
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should run successfully if a removed file was added to commit: $returnValue" 0 $?
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null