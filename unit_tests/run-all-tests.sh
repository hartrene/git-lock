#!/bin/sh

. ./unit-test-util.sh 

# create the result file and make sure it gets removed
testResultsFile="${TEST_BASE_DIR}/testResultsFile.out"
touch "$testResultsFile"
trap "rm $testResultsFile; exit" INT TERM EXIT

# run all tests
./server-tests.sh "${1:-}"
./client-tests.sh "${1:-}"
./pre-receive-hook-tests.sh "${1:-}"

echo ""
echo "#"
echo "# Aggregated Test Report"
echo "#"
cat "$testResultsFile"

# Fail this script if not all tests where executed successful
readProperty failedTests "$testResultsFile" "tests failed"
if [ "$failedTests" -ne 0 ]; then
	exit 1
else
	exit 0
fi
