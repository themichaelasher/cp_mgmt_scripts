#!/bin/bash
#
# Script to set the log forwarding settings on the gateway objects.
#
# Changelog
# - 2023020302 - Added better output for data. 
# - 2023020301 - Initial script creation by (masher|ianw)
#
###############################################################
# Fetch the number of domains. 
_domains=`mgmt_cli -r true show domains -f json | jq -r .total`

# This is one of the global default timers defined in R81.10
# There might be other options including customer created events. 
# This should be changed accordingly.

DEFAULTTIME="Midnight"
OUTPUTDIR="/tmp/`whoami`-clf"

if [ ! -d ${OUTPUTDIR} ]; 
then
    mkdir ${OUTPUTDIR}
fi


function mdsdomains(){
    DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
    # There are no gateways defined on the global domain, so this is excluded.
    # DOMAINS+=("Global")
}

function docleanup(){
    pushd ${OUTPUTDIR}
    for i in *.id 
    do 
        mgmt_cli -s ${i} logout
    done
    rm *.id
    popd
    rm -r ${OUTPUTDIR}
    exit 0
}
# Using the generic API, find the complete list of options in the current domain when called.

function find_scheduled_times(){
    domain_scheduled_events="`mgmt_cli -r true -d LAB show generic-objects class-name com.checkpoint.objects.classes.dummy.CpmiScheduledEvent -f json details-level full  | jq '.objects[]|.name' | tr '\n' ' '`"

    # Verify that the DEFAULTTIME setting actually exists. If not, the script could exit and cleanup or set the default value to Midnight
    if [[ ! "${domain_scheduled_events[@]}" =~ "${DEFAULTTIME}" ]]; then
        echo "Error: ${DEFAULTTIME} is not defined in the ${domain}"
        echo "Please adjust the scheduled time to be a properly defined event"
        echo "Cleaning up and exiting"
        #docleanup
    fi

    DEFAULTTIMEUID="$(mgmt_cli show generic-objects class-name com.checkpoint.objects.classes.dummy.CpmiScheduledEvent -f json details-level full -f json | jq -r '.objects[]|select(.name | contains ("'"${DEFAULTTIME}"'"))|.uid')"
  
}

# Run throgh the process of setting eash GW to the proper log forwarding destination.
# 
function set_log_forwarding(){
    mdsdomains
    for domain in ${DOMAINS[@]}; 
    do
        # Authenticate to the domain 
        mgmt_cli -r true -d ${domain} login >  "${OUTPUTDIR}/${domain}.id"
        
        # set environment variable for simpler command
        #
        export MGMT_CLI_SESSION_FILE="${OUTPUTDIR}/${domain}.id"
        
        # Fetch the GW list and UIDs
        # The CSV file generated in the be adjusted slightly. 

        mgmt_cli show gateways-and-servers -f json | jq '.objects[]|select(.type | contains ("CpmiGatewayCluster") or contains("simple-gateway"))|[.name,.uid]|@csv' | sed -e 's/[\"]//g' > ${OUTPUTDIR}/${domain}.gw.list
        
        # Rotate through GW list and find default log server
        # Right now, this assumes a single primary destination. This will need to be adjusted down the road.
        # This will read the columns in ${domain}.gw.list and dump them into a new csv file.
        # Since the sendLogsTo UID is output rather than the checkpoint host name, this can skip a step.       
        while IFS=, read -r name uid
        do 
          echo "$name,$uid","$(mgmt_cli show generic-object uid $uid -f json | jq '.logServers.sendLogsTo[]')" ; done < ${OUTPUTDIR}/${domain}.gw.list > ${OUTPUTDIR}/${domain}.gwandlogserver.list
        done
    
        # Now we have the GW name, GW UID, and Log Server UID defined, let's fetch the uid for the "DEFAULTTIME" 
        find_scheduled_times

        # Now that the UID is known for the default log server and time schedule, now it's time to make the changes
        while IFS=, read -r gwname gwuid loguid
        do
          echo "Changing ${gwname}"
          mgmt_cli set generic-object uid ${gwuid} logPolicy.forwardLogs true logPolicy.logForwardTarget ${loguid} logPolicy.logForwardSchedule ${DEFAULTTIMEUID}
        done < ${OUTPUTDIR}/${domain}.gwandlogserver.list:wq

        # Publish Changes and logout
        echo "Publishing all changes."
        mgmt_cli publish # 2>/dev/null >/dev/null
        mgmt_cli logout #2>/dev/null >/dev/null
        rm ${OUTPUTDIR}/${domain}.id
        unset MGMT_CLI_SESSION_FILE
    done
}

set_log_forwarding
docleanup