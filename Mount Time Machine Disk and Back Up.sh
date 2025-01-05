#!/bin/sh

output() {
	response=$1
	status=$2
	echo "$response"
	osascript -  "$response" "$status"  <<EOF
	on run argv -- argv is a list of strings
		display notification (item 1 of argv) with title (item 2 of argv)
	end run
EOF
}

getValueFromJSON() {
	json_str="$1"
	key_path="$2"
	value=$(osascript -l JavaScript -  "$json_str" "$key_path"  <<EOF
		function run(input){
			let jsonStr = input[0];
			let keyPath = input[1];
			let bracketedKeys = '';
			let plist = JSON.parse(jsonStr);
			let current = plist;
			
			keys = keyPath.split('.');
			for (let i = 0; i < keys.length; i++) {
				let key = keys[i];
				try {
					current = current[key];
				} catch(e) {
					return 'Key "' + key + '" not found'
					break;
				}
			}
			return current;
		}
EOF)
	echo "$value"
}

unmount() {
	backup_succeeded=$1
	backup_status_message=$2
	response="Time Machine backup completed"
	unmount_err=$(diskutil unmount "$backup_uuid" 2>&1 > /dev/null)
	if [ "$?" -ne 0 ]; then
		mount_status="the backup drive failed to unmount"
		if [[ "$backup_succeeded" = true ]];
		then
			output "$response, but $mount_status." "Unmount Failed"
		else
			response="Backup stopped before completing"
			output "$response and $mount_status." "Backup and Unmount Failed"
		fi
	else
		mount_status="the backup drive was unmounted successfully"
		if [[ "$backup_succeeded" = true ]];
		then
			output "$response and $mount_status." "Backup Complete"
		else
			response="Backup stopped before completing"
			output "$response, but $mount_status." "Backup and Unmount Failed"
		fi
	fi 
		
}

backup_drive=$(tmutil destinationinfo | sed -rn 's/(Name +\: )//p')
tm_timeout=120


# Convert saved time to a Unix timestamp
start_timestamp=$(date +%s)

drive_info=$(diskutil info "$backup_drive" 2>&1 > /dev/null)
if [[ $drive_info = "Could not find disk: $backup_drive" ]];
	then
	output "Time Machine disk \"$backup_drive\" is not connected." "Backup Failed"
	exit
fi
backup_uuid=$(diskutil info "$backup_drive" | sed -rn "s/ +Volume UUID\: +//p")
diskutil mount "$backup_uuid"

tmutil startbackup

# Sometimes it takes a few seconds for Time Machine to start. 
while [ $(tmutil currentphase) == 'BackupNotRunning' ];
	do
	tm_timeout=$(($tm_timeout-1))
	if [[ $tm_timeout -le 0 ]];
		then
		unmount false "Time Machine backup to \"$backup_drive\" was unable to start."
		exit
	fi
	sleep 1
done;

tm_stopped=false
# Wait until Time Machine is no long running, then unmount.
while [ $(tmutil currentphase) != 'BackupNotRunning' ]; 
	do 
	tm_status_json=$(tmutil status | sed 's/Backup session status://g' | plutil -convert json - -o - )
	backup_phase=$(getValueFromJSON "$tm_status_json" "BackupPhase")
	percent=$(getValueFromJSON "$tm_status_json" "Progress.Percent")
	
	if [[ $percent = 'Key "Percent" not found' ]];
		then
		percent="0"
	fi
	
	current_timestamp=$(date +%s)
	
	# Calculate the difference in seconds
	time_difference=$((current_timestamp - start_timestamp))
	
	# Convert the difference to hours:minutes:seconds
	hours="$((time_difference / 3600))"
	
	if [[ ${#hours} = 1 ]];
		then
		hours="0$hours"
	fi
	minutes="$(((time_difference % 3600) / 60))"
	if [[ ${#minutes} = 1 ]];
		then
		minutes="0$minutes"
	fi
	seconds="$((time_difference % 60))"
		if [[ ${#seconds} = 1 ]];
		then
		seconds="0$seconds"
	fi
	echo "-----------------------------------------"
	echo "Waiting for backup to complete."
	echo "Time Elapsed: $hours:$minutes:$seconds"
	echo "Backup Phase: $backup_phase"
	echo "Percent: $percent"
	if [[ $(tmutil currentphase) = 'Stopping' ]];
		then
		tm_stopped=true
		break
	fi
	sleep 10
done;

if [[ "$tm_stopped" = true ]];
then
	unmount false "Backup stopped before completing"
	exit
fi
unmount true "Time Machine backup completed"


