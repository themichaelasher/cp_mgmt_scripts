#!/bin/bash
#
# Function:
#   Show interface statistics due to cosmetic issue in show interface <name> statistics q
#
# Usage:
#   ptccli-wrapper.sh <DOMAIN> <ptc_cli command>
#
# Latest Revision: 01-Oct-2018

## Usage notices
usage(){
    echo "Usage: $_ <interfacename>"
    echo -e "\n"
    echo "Example: ifstats eth0"
    echo -e "\n"
    exit;
}

args=$#
if [[ $args -lt 1 ]];
 then
        usage
fi

if [[ "$1" =~ -/* ]];
  then
    usage
fi
# Map Arguments
interface="$1"
echo ${interface}
## Fetch Domains
#interfaces=(`ifconfig | grep Link | awk '{print $1}'| tr '\n' ' '`)
interfaces=(`ip link show  | pcregrep '^\d+:' | grep -v NONE | awk -F : '{print $2}' | sed -e 's/@bond[0-9]*//g'`)
intmatch="`echo ${interfaces[@]}| grep -ow ${interface}`"


# Verify ARGV1 is a proper interface
if ! [[ "$interface" == "$intmatch" ]];
then
        echo "Error: $interface is not a valid interface"
        echo -e "\n"
        ERRORCOUNT=1
        exit 1;
fi

if [[ "$ERRORCOUNT" -ne "1" ]];
  then
    echo -ne "\nStatistics:\n$(ifconfig ${interface} | egrep  -ie 'packets|bytes' | sed -e 's/^ *//g'|sed -e 's/TX bytes/\nTX bytes/g')\n"
fi