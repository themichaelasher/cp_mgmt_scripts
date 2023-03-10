#!/bin/bash
#
# Script to set the log forwarding settings on the gateway objects.
#
# Changelog
# - 2023021401 - Added logging output for visibilidy to all commands.
# - 2023021301 - Initial script creation by (masher|ianw)
#
# TODO:
# - Show changes before publish
# - Cleanup error messages on missing files
#
###############################################################

SHOWWARNING=1
DEBUGLOG="`pwd`/add-log-forwarders.log"
[[ -f ${DEBUGLOG} ]] && mv ${DEBUGLOG}{,.bak}
[[ ! -f ${DEBUGLOG} ]] && touch ${DEBUGLOG}


# This looks a little odd, but this will allow logging of all commands and output to a single file.
#
set -x
(

# This is one of the global default timers defined in R81.10
# There might be other options including customer created events.
# This should be changed accordingly.
DEFAULTTIME="Midnight"
OUTPUTDIR="/tmp/`whoami`-clf"

# Create temp directory
if [ ! -d ${OUTPUTDIR} ];
then
  mkdir ${OUTPUTDIR}
fi

# Cleanup old files.
function docleanup(){
  rm -r ${OUTPUTDIR}
  exit 0
}

function showwarning(){
  if [[ $SHOWWARNING -eq 1 ]];
  then
    echo -ne "\n\n"
    echo  "===================================================================="
    echo -ne "WARNING:\n"
    echo -ne "\tThis script has been tested in multiple environments\n"
    echo -ne "\tand will make changes to the MDS. Please thoroughly\n"
    echo -ne "\treview and validate in your own testing environment\n"
    echo -ne "\tbefore configuring in production. Ensure that your\n"
    echo -ne "\trevision history is available to your users as well\n"
    echo -ne "\tas a confirming the availability of a current MDS backup\n"
    echo -ne "\n\n Press CTRL-C to cancel or wait 30 seconds to continue.\n"
    echo  "===================================================================="
    sleep 30
  fi
 }
# Using the generic API, find the complete list of options in the current domain when called.
function find_scheduled_times(){
  domain_scheduled_events="$(mgmt_cli show generic-objects class-name com.checkpoint.objects.classes.dummy.CpmiScheduledEvent -f json details-level full  | jq '.objects[]|.name' | tr '\n' ' ')"
  # Verify that the DEFAULTTIME setting actually exists. If not, the script could exit and cleanup or set the default value to Midnight
  if [[ ! "${domain_scheduled_events[@]}" =~ "${DEFAULTTIME}" ]]; then
    echo "Error: ${DEFAULTTIME} is not defined in the ${domain}"
    echo "Please adjust the scheduled time to be a properly defined event"
    echo "Cleaning up and exiting"
    #docleanup
  fi

  DEFAULTTIMEUID="$(mgmt_cli  show generic-objects class-name com.checkpoint.objects.classes.dummy.CpmiScheduledEvent -f json details-level full -f json | jq -r '.objects[]|select(.name | contains ("'"${DEFAULTTIME}"'"))|.uid')"
}

# Run throgh the process of setting eash GW to the proper log forwarding destination.
function set_log_forwarding(){
  showwarning
  declare -a DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
  for domain in "${DOMAINS[@]}"
  do
    # Authenticate to the domain
    echo -e "\nChecking: ${domain}"
    mgmt_cli -r true -d ${domain} login > ${OUTPUTDIR}/${domain}.id
        export MGMT_CLI_SESSION_FILE=${OUTPUTDIR}/${domain}.id

    # Set a session name to dump the show-changes
    mgmt_cli set session new-name "${domain}.log.changes"

    # See if "DEFAULTTIME" is defined.
    find_scheduled_times

    # Fetch the GW list and UIDs
    # The CSV file generated in the be adjusted slightly.

    mgmt_cli show gateways-and-servers -f json | jq '.objects[]|select(.type | contains("CpmiGatewayCluster") or contains("simple-gateway") or contains("CpmiVsxNetobj") or contains("CpmiVsNetobj") or contains("CpmiVsxClusterNetobj"))|[.name,.uid]|@csv' | sed -e 's/[\"]//g' >> ${OUTPUTDIR}/${domain}.gw.list


    # Rotate through GW list and find default log server
    # Right now, this assumes a single primary destination. This will need to be adjusted down the road.
    # This will read the columns in ${domain}.gw.list and dump them into a new csv file.
    # Since the sendLogsTo UID is output rather than the checkpoint host name, this can skip a step.
    while IFS=, read -r name uid
    do
      echo "$name,$uid,$(mgmt_cli show generic-object uid $uid -f json | jq '.logServers.sendLogsTo[]')"
    done < ${OUTPUTDIR}/${domain}.gw.list >> ${OUTPUTDIR}/${domain}.gwandlogserver.list

    # Now that the UID is known for the default log server and time schedule, now it's time to make the changes
    while IFS=, read -r gwname gwuid loguid
    do
      logname="`mgmt_cli show generic-object uid ${loguid} -f json |jq -r .name`"
      echo -e "  Changing: ${gwname} to forward to ${logname} at ${DEFAULTTIME})"
      mgmt_cli set generic-object uid ${gwuid} logPolicy.forwardLogs true logPolicy.logForwardTarget ${loguid} logPolicy.logForwardSchedule ${DEFAULTTIMEUID}
    done < ${OUTPUTDIR}/${domain}.gwandlogserver.list

    # Publish Changes and logout
    echo "  Publishing all changes to database."
    mgmt_cli publish 2>/dev/null >/dev/null
    echo "  Logging out of ${domain}"
    mgmt_cli logout  2>/dev/null >/dev/null
        unset MGMT_CLI_SESSION_FILE
  done
}

## Start the routines
set_log_forwarding
docleanup
echo -ne "\nScript Completed. Debug log is saved to ${DEBUGLOG}\n\n"
) 2> ${DEBUGLOG}
