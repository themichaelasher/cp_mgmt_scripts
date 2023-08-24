#!/bin/bash
#
# Script to set the log forwarding settings on the gateway objects.
#
# Changelog
# - 2023082302 - Corrected default time check; added DRYRUN option
# - 2023082301 - Placed gw_server_list in a proper loop for API limits (default: 50)
# - 2023021401 - Added logging output for visibilidy to all commands.
# - 2023021301 - Initial script creation
########################################################################################

# Show the 30 second warning. Set to 0 to disable it
SHOWWARNING=1
# If set to 1 , a notice is presented and all sessions changes are discarded
DRYRUN=1

# CLI colors for screen output
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m" ## No Color

# Logging requirements
DEBUGLOG="`pwd`/dbg.add-log-forwarders.log"
[[ -f ${DEBUGLOG} ]] && mv ${DEBUGLOG}{,.bak}
[[ ! -f ${DEBUGLOG} ]] && touch ${DEBUGLOG}

# This looks a little odd, but this will allow logging of all commands and output to a single file.
#
set -x
(

# This is one of the global default timers defined in R81.10
# There might be other options including customer created events.
# This should be changed accordingly.
#DEFAULTTIME="SuperTACO" ## RANDOM TESTING VALUE
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
    echo -ne "${RED}WARNING${NC}:\n"
    echo -ne "\tThis script has been tested in multiple environments\n"
    echo -ne "\tand will make changes to the MDS. Please thoroughly\n"
    echo -ne "\treview and validate in your own testing environment\n"
    echo -ne "\tbefore configuring in production. Ensure that your\n"
    echo -ne "\trevision history is available to your users as well\n"
    echo -ne "\tas a confirming the availability of a current MDS backup\n"
    echo -ne "\n\n ${RED}Press CTRL-C to cancel or wait 30 seconds to continue.${NC}\n"
    echo  "===================================================================="
    sleep 30
  fi
 }

function dryrun(){
  if [[ $DRYRUN -eq 1 ]];
  then
    echo -ne "\n\n"
    echo  "===================================================================="
    echo -ne "${RED}DRYRUN${NC} is set to ${CYAN}1${NC} in the script\n"
    echo -ne "No changes will be committed\n"
    echo -ne "To enable changes, edit the script and change DRYRUN=${RED}1${NC} to DRYRUN=${CYAN}0${NC}\n"
    echo  "===================================================================="
    sleep 5
  elif  [[ $DRYRUN -ne 0 ]];
  then
      echo "$DRYRUN is not properly defined. Discarding all changes"
      exit 1;
  fi
}
# Using the generic API, find the complete list of options in the current domain when called.
function find_scheduled_times(){
  DOMAINSKIP=0 ## Setting a default value here.
  declare -a domain_scheduled_events="$(mgmt_cli show generic-objects class-name com.checkpoint.objects.classes.dummy.CpmiScheduledEvent -f json details-level full  | jq '.objects[]|.name' | tr '\n' ' ')"
  # Verify that the DEFAULTTIME setting actually exists. If not, the script could exit and cleanup or set the default value to Midnight
  if [[ ! "${domain_scheduled_events[@]}" =~ "${DEFAULTTIME}" ]];
  then
    echo -ne "${RED}Error:${NC} ${DEFAULTTIME} is not defined in the ${CYAN}${domain}${NC}\n"
    echo "Please adjust the scheduled time to be a properly defined event"
    echo -ne "Skipping ${CYAN}${domain}${NC}\n"
    DOMAINSKIP=1
  fi

  DEFAULTTIMEUID="$(mgmt_cli  show generic-objects class-name com.checkpoint.objects.classes.dummy.CpmiScheduledEvent -f json details-level full -f json | jq -r '.objects[]|select(.name | contains ("'"${DEFAULTTIME}"'"))|.uid')"
}

# Run throgh the process of setting eash GW to the proper log forwarding destination.
function set_log_forwarding(){
  showwarning
  dryrun
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
    if  [[  ${DOMAINSKIP} -eq 0 ]];
    then
      # Fetch the GW list and UIDs
      # The CSV file generated in the be adjusted slightly.
      # Counter and offset is needed to cycle through all possible objects.
      _counter=0
      
      # Fetch all of the gateways
      touch ${OUTPUTDIR}/${domain}.gw.list
      while [[ $_counter -lt $GWCOUNT ]]; do
        mgmt_cli show gateways-and-servers -f json limit 50 offset $_counter | jq -r '.objects[]|[.name,.uid,.type]|@csv' >> ${OUTPUTDIR}/${domain}.gw.list
        let "_counter = $_counter+50"
      done
      echo "  Filtering GW list"
      grep -v -E "placeholder|member|placer|checkpoint-host|Member|host" ${OUTPUTDIR}/${domain}.gw.list  >  ${OUTPUTDIR}/${domain}.gw.filtered.list

      # Rotate through GW list and find default log server
      # Right now, this assumes a single primary destination. This will need to be adjusted down the road.
      # This will read the columns in ${domain}.gw.list and dump them into a new csv file.
      # Since the sendLogsTo UID is output rather than the checkpoint host name, this can skip a step.
      echo "  Fetching defined logServers"
      while IFS=, read -r name uid type
      do
        echo "$name,$uid,$(mgmt_cli show generic-object uid $uid -f json | jq '.logServers.sendLogsTo[]')"
      done < ${OUTPUTDIR}/${domain}.gw.filtered.list >> ${OUTPUTDIR}/${domain}.gwandlogserver.list

      # Now that the UID is known for the default log server and time schedule, now it's time to make the changes
      while IFS=, read -r gwname gwuid loguid
      do
        logname="$(mgmt_cli show generic-object uid $loguid -f json |jq -r .name)"
        if [[ -z "${logname}" && -n "${logname}" ]]; then
          echo -e "  Error: Unable to find log server name for ${gwname} (Loguid: $loguid)"
        else
          echo -e "  Changing: ${gwname} (Forward to ${logname} at ${DEFAULTTIME})"
          #mgmt_cli set generic-object uid ${gwuid} logPolicy.forwardLogs true logPolicy.logForwardTarget ${loguid} logPolicy.logForwardSchedule ${DEFAULTTIMEUID}
        fi
      done < ${OUTPUTDIR}/${domain}.gwandlogserver.list

      # Publish Changes and logout
      if [[ $DRYRUN -eq 1 ]];
      then
        echo -ne "  ${CYAN}TESTING: discarding all changes${NC}\n"
        mgmt_cli discard 2>/dev/null >/dev/null
      elif  [[ $DRYRUN -eq 0 ]];
      then
        echo "  Publishing all changes to database."
        mgmt_cli publish 2>/dev/null >/dev/null
      fi
      echo "  Logging out of ${domain}"
      mgmt_cli logout  2>/dev/null >/dev/null
      unset MGMT_CLI_SESSION_FILE
    fi
    done
}

## Start the routines
GWCOUNT="$(mgmt_cli -r true show gateways-and-servers -f json | jq .total)"
set_log_forwarding
docleanup
echo -ne "\nScript Completed. Debug log is saved to ${DEBUGLOG}\n\n"
) 2> ${DEBUGLOG}
