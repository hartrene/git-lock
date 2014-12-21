#!/bin/bash

# Unit-tests of the git pre-receive hook

# Run thie client-test setup
. ./client-test-base.sh "$@"

# Add the git-lock script to the path to be able to simulate a run on a client
export PATH=$PATH:$(pwd)/..

initGitRepositories() {
	# Create new bare origin repository
	mkdir origin-repo
	cd origin-repo
	returnValue=$(git init --bare)
	returnValue=$(lockClient init --bare)
	assertEquals "lockClient init in a bare repository should complete sucessfully: $returnValue" 0 $?
	cd ..
	
	# Clone the origin repository
	returnValue=$(git clone origin-repo working-repo 2>/dev/null)
	cd working-repo
	
	# Add and commit a file so that it creates the master branch
	touch "$TEST_FILE"
	result=$(git add .)
	result=$(git commit -m"Init commit")
	
	# Init git lock
	returnValue=$(lockClient init)
	assertEquals "lockClient init should complete sucessfully: $returnValue" 0 $?
}

callHook() {
	# Commit changes to the working-repo
	returnValue=$(git commit -m 'Committing changes')
	assertEquals "Git commit should run successfully: $returnValue" 0 $?
	
	# Push the changes to the origin to trigger the pre-receive hook
	logDebug "Push changes to origin, which will trigger the pre-receive hook"
	git push origin master &> git-push.log
	returnCode=$?
	
	# Get all git-lock log messages
	returnValue=$(cat git-push.log)
	logDebug "$returnValue"
	echo "$returnValue"
	return $returnCode
}

testInitShouldInstallPreReceiveHook() {
	initGitRepositories
	returnValue=$(ls $LOCK_CLIENT_TEST_DIR/origin-repo/hooks/pre-receive)
	assertEquals "git-lock init should have installed the pre-receive hook into bare repository: $returnValue" 0 $?
	returnValue=$(ls $LOCK_CLIENT_TEST_DIR/working-repo/.git/hooks/pre-receive)
	assertEquals "git-lock init should have installed the pre-receive hook into normal repository:: $returnValue" 0 $?
}

testShouldSuccessfullyExecutePreReceiveHookDuringPush() {
	initGitRepositories
	echo "adsf" > "$TEST_FILE"
	mkdir "$TEST_FILE_2_DIR"
	echo "adsf" > "$TEST_FILE_2"
	
	# Stage the changed file
	returnValue=$(git add "$TEST_FILE")
	returnValue=$(git add "$TEST_FILE_2")
	assertEquals "Git add should run successfully: $returnValue" 0 $?
	
	# Run the hook
	returnValue=$(callHook)
	assertEquals "pre-commit hook should execute successfully: $returnValue" 0 $?
}

# run the tests with shunit2
. ./shunit2
saveTestResults > /dev/null
