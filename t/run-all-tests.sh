#!/bin/sh

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

. ./unit-test-util.sh

# create the result file and make sure it gets removed
testResultsFile="${TEST_BASE_DIR}/testResultsFile.out"
touch "$testResultsFile"
trap "rm $testResultsFile; exit" INT TERM EXIT

# run all tests
./server-tests.sh "${1:-}"
./client-tests.sh "${1:-}"
./pre-commit-hook-tests.sh "${1:-}"
./pre-receive-hook-tests.sh "${1:-}"
./post-merge-hook-tests.sh "${1:-}"

echo "" > /dev/tty
echo "#" > /dev/tty
echo "# Aggregated Test Report" > /dev/tty
echo "#" > /dev/tty
cat "$testResultsFile" > /dev/tty

# Fail this script if not all tests where executed successful
readProperty failedTests "$testResultsFile" "tests failed"
if [ "$failedTests" -ne 0 ]; then
	exit 1
else
	exit 0
fi