#!/bin/bash
# Gets called from the lock-client-lib.sh when executing server calls during the unit-test execution.
# It calls the server without actually using ssh.

count=0
paramsToSend=()

# Remove the single quotes from each param as ssh is removing them as well
# It also combines parameter which have been separated e.g. 'My<\n>Project' -> MyProject
for param in $@; do
	count=$(($count+1))

	if [ $count -eq 1 ]; then 
		continue;
	fi
	
	if [ "$newParam" == "" ]; then
		newParam="$param"
	else
		newParam="$newParam $param"
	fi
	
	case "$newParam" in 
		*\') # Ends with a single quote
			paramsToSend+=("${newParam//\'/}")
			newParam="";;
		\'*) # Starts with a single quote
			continue;;	
		*) 	
			paramsToSend+=("${newParam//\'/}")
			newParam="";;
	esac
done

$1/../lock-server.sh "${paramsToSend[@]}"
