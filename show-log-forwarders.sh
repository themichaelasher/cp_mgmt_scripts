#!/bin/bash
#
# Script to retrieve the log forwarding settings on the gateway objects.
# Outputs data to `pwd`/final-output.csv and to SSH/console session.
# This is only written for MDSM. 
#
# Changelog
# - 2023081501 - Initial script creation. 
###############################################################

# Pull the total number of gateways and objects
GWCOUNT="$(mgmt_cli -r true show gateways-and-servers -f json | jq .total)"
declare -a DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)

# Colors for final console output
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m" ## No Color

for _domain in ${DOMAINS[@]}
do
  # Login and save session to file
  #
  mgmt_cli -r true -d ${_domain} login > "${_domain}.id"
  export MGMT_CLI_SESSION_FILE="${_domain}.id"

  # Counter and offset is needed to cycle through all possible objects.
  _counter=0 

  # Fetch all of the gateways
  #
  echo -e "Fetching GW and Servers ${CYAN}${_domain}${NC}"
  touch "gw.${_domain}.list"
  while [[ $_counter -lt $GWCOUNT ]]; do
    mgmt_cli show gateways-and-servers -f json limit 50 offset $_counter | jq -r '.objects[]|[.name,.domain.name,.type,.uid]|@csv' >> "gw.${_domain}.list"
    let "_counter = $_counter+50"
  done

  # Filter out the unneeded objects.
  # This filter has some "placeholder" gateways and other objects that are unnecessary
  #
  echo "    Filtering GW list"
  grep -v -E "placeholder|member|placer|checkpoint-host|CpmiVsClusterNetobj|Member" "gw.${_domain}.list"  >  "gw.${_domain}.filtered.list"

  # Fetch the log server information
  # This information isn't necessary, but it is nice to know.
  #
  echo "    Fetching sendLogTo values"
  touch "gw.${_domain}.withloguid.list"
  while IFS=, read -r name domain type uid
  do
    echo "$name,$domain,$type,$uid,$(mgmt_cli show generic-object uid $uid -f json | jq '.logServers.sendLogsTo[]')"
  done < "gw.${_domain}.filtered.list"  >> "gw.${_domain}.withloguid.list"

  # Fetch the log forwarding target uid and convert to name
  # 
  echo "    Fetching logForwardTarget values"
  touch "gw.${_domain}.withlogforwardtarget.list"
  while IFS=, read -r name domain type uid loguid
  do
    _lft="$(mgmt_cli show generic-object uid $uid -f json | jq '.logPolicy.logForwardTarget')"
    if [[ -z "${_lft}" && -n "${_lft}" ]]; then
      echo "${name},${domain},${type},${loguid},undefined"
    else
      echo "$name,$domain,$type,$uid,${loguid},$(mgmt_cli show generic-object uid ${_lft} -f json | jq -r .name)"
    fi
  done < "gw.${_domain}.withloguid.list" >> "gw.${_domain}.withlogforwardtarget.list"

  # Fetch the log forwarding schedule uid and convert to name
  #
  echo "    Fetching logForwardSchedule values"
  touch "gw.${_domain}.withschedule.list"
  while IFS=, read -r name domain type uid loguid logforwardname
  do
    _schedule="$(mgmt_cli show generic-object uid $uid -f json | jq '.logPolicy.logForwardSchedule')"
    if [[ -z "${_schedule}" && -n "${_schedule}" ]]; then
      echo "${name},${domain},${type},${loguid},${logforwardname},undefined"
    else
      echo "$name,$domain,$type,$uid,${loguid},${logforwardname},$(mgmt_cli show generic-object uid $_schedule -f json | jq -r .name)"
    fi
  done < "gw.${_domain}.withlogforwardtarget.list" >> "gw.${_domain}.withschedule.list"

  # Finally, convert the log server and convert to name
  # 
  while IFS=, read -r name domain type uid loguid logforwardname logschedulename
  do
    if [[ -z "${loguid}" && -n "${loguid}" ]]; then
      echo "${name},${domain},${type},No Log Server Defined,${logforwardname},${logschedulename}"
    else
      logserver="$(mgmt_cli show generic-object uid $loguid -f json | jq '.name')"
      if [ $? -eq 0 ]; then
        echo "${name},${domain},${type},${logserver},${logforwardname},${logschedulename}"
      else
        echo "${name},${domain},${type},Command Failed,${logforwardname},${logschedulename}"
      fi
    fi
  done < "gw.${_domain}.withschedule.list" >> "gw.${_domain}.converted.list"
  
  # Properly logout of the API 
  #
  echo -e "    ${CYAN}${_domain} completed.${NC} \n\n"
  mgmt_cli logout 1> /dev/null
  unset MGMT_CLI_SESSION_FILE
done

# Build the final CSV file 
#
echo '"Gateway","Domain","Object Type","Defined Log Server","Log Forward Target","Log Forward Schedule"' > final-output.csv
cat *.converted*.list >> final-output.csv

# Cleanup junk files
rm *.list
rm *.id

# Display CSV to screen.
echo -e "${CYAN}Final output is in ${RED}$(pwd)/final-output.csv ${NC}"
echo -ne "\n\n"
cat final-output.csv | column -t -s,  | sed -e 's/"//g'

# Fin.
