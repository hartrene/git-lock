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

# lock-server.sh script which will delegate all commands to lock-server-lib.sh

LOG_LEVEL_QUIET=0
LOG_LEVEL_ERROR=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3
logLevel=$LOG_LEVEL_INFO

# Check if a log level was given
param="${1:-}"
if [ -n "$param" ]; then
	case "$param" in
		--quiet) logLevel=$LOG_LEVEL_QUIET; shift;;
		--error) logLevel=$LOG_LEVEL_ERROR; shift;;
		--info) logLevel=$LOG_LEVEL_INFO; shift;;
		--debug) logLevel=$LOG_LEVEL_DEBUG; shift;;
	esac
fi

# Function to log messages to the proper output device
logMessage() {
	# Log messages to stderr so that they don't get mixed up
	# With the function return value which will be send to stdout
	echo "  [LOCK SERVER] $1" >&2
}

# Check if the working dir is set
if [ -z "${LOCK_SERVER_DIR:-}" ]; then
	errorMsg="Environment variable LOCK_SERVER_DIR not found"
	logMessage "$errorMsg"
	echo "$errorMsg"
	exit 1
fi

# Import the lock-server functions
. "${LOCK_SERVER_BIN_DIR}lock-server-lib.sh"

# Delegate the command
returnValue=$(lockServer "$@")
returnCode=$?

# Return the values
if [ -n "$returnValue" ]; then
	echo "$returnValue"
fi

exit $returnCode