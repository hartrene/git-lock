#!/bin/bash

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
. "${LOCK_SERVER_BIN_DIR}/lock-server-lib.sh"

# Delegate the command
returnValue=$(lockServer "$@")
returnCode=$?

# Return the values
if [ -n "$returnValue" ]; then
	echo "$returnValue"
fi

exit $returnCode
