#!/bin/sh

if [ "x$DEBUG" != "x" ]; then
	set -x
fi

# The directory to store the two state files - /config is a docker standard
OLD_IP_FILE=/tmp/MAM.ip
RESPONSE_FILE=/tmp/MAM.output
TEMP_COOKIE_FILE=/tmp/MAM.cookies
COOKIE_FILE=/config/MAM.cookies


if [ "x$interval" == "x" ]; then
	echo "Running with default interval of 1 minute"
	SLEEPTIME=60
else
	if [ "$interval" -lt "1" ]; then
		echo "Cannot set interval to less than 1 minute"
		echo "  => Running with default interval of 60 seconds"
		SLEEPTIME=60
	else
		echo "Running with an interval of $interval minute\(s\)"
		SLEEPTIME=`expr $interval \* 60`
	fi
fi

grep mam_id ${COOKIE_FILE} > /dev/null 2>/dev/null
if [ $? -ne 0 ]; then
	if [ "x$mam_id" == "x" ]; then
		echo "no mam_id, and no existing session."
		exit 1
	fi

	echo "No existing session, creating new cookie file using mam_id from environment"
	curl -s -b mam_id=${mam_id} -c ${COOKIE_FILE} https://t.myanonamouse.net/json/dynamicSeedbox.php > $RESPONSE_FILE

	grep '"Success":true' $RESPONSE_FILE > /dev/null 2>/dev/null
  if [ $? -ne 0 ]; then
		echo "mam_id passed on command line is invalid"
		exit 1
	else
		grep mam_id ${COOKIE_FILE} > /dev/null 2>/dev/null
		if [ $? -ne 0 ]; then
			echo "Command successful, but failed to create cookie file."
			exit 1
		else
			echo "New session created."
		fi
	fi
else
	curl -s -b $COOKIE_FILE -c $COOKIE_FILE https://t.myanonamouse.net/json/dynamicSeedbox.php > $RESPONSE_FILE
	grep '"Success":true' $RESPONSE_FILE > /dev/null 2>/dev/null
  	if [ $? -ne 0 ]; then
		echo "Response: `cat $RESPONSE_FILE`"
		echo "Current cookie file is invalid.  Please delete it, set the mam_id, and restart the container."
		exit 1
	else
		echo "Session is valid"
	fi

fi

OLD_IP=`cat $OLD_IP_FILE 2>/dev/null`

while [ $PPID -ne 1 ]; do
	OLD_IP=`cat $OLD_IP_FILE 2>/dev/null`
	NEW_IP=`curl -s ip4.me/api/ | md5sum - | awk '{print $1}'`

	if [ "x$DEBUG" != "x" ]; then
		echo "Current IP:  `curl -s ip4.me/api/`"
	fi
	
	# Check to see if the IP address has changed
	if [ "$OLD_IP" != "$NEW_IP" ]; then
    echo "New IP detected"
    # Save cookie jar to temporary file, to not overwrite
    # with empty cookies on failed requests
    curl -s -b $COOKIE_FILE -c $TEMP_COOKIE_FILE https://t.myanonamouse.net/json/dynamicSeedbox.php > $RESPONSE_FILE

		grep -E 'No Session Cookie|Invalid session' $RESPONSE_FILE > /dev/null 2>/dev/null
		if [ $? -eq 0 ]; then
			echo "Response: `cat $RESPONSE_FILE`"
			echo "Current cookie file is invalid.  Please delete it, set the mam_id, and restart the container."
			exit 1
		fi
	
    # If that command worked, and we therefore got the success message
    # from MAM, update the OLD_IP_FILE for the next execution
		grep '"Success":true' $RESPONSE_FILE > /dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "Response:  \"`cat $RESPONSE_FILE`\""
      # Update COOKIE_FILE only on successful requests
      mv $TEMP_COOKIE_FILE $COOKIE_FILE
      echo $NEW_IP > $OLD_IP_FILE
      OLD_IP=$NEW_IP
		else
			grep "Last change too recent" $RESPONSE_FILE > /dev/null 2>/dev/null
			if [ $? -eq 0 ]; then
				echo "Last update too recent - sleeping"
			else
				echo "Response: `cat $RESPONSE_FILE`"
				echo "Invalid response"
				exit 1
			fi
    fi
	else
		echo "No IP change detected: `date`"
	fi
	sleep $SLEEPTIME

	# Empty the IP file if it has not been rotated for more than 30 days, this will enforce session freshness.
	find $OLD_IP_FILE -mtime +30 -delete
done
