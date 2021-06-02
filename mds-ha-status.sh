#!/bin/bash
#

# Fetch total domain count. 

_domains=`mgmt_cli -r true show domains -f json | jq -r .total`

function mdsdomains(){
    DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
    # Add Global domain since it isn't included in the show-domains list
    DOMAINS+=("Global")
}

# Set the HA State on the domain (or SMS)
function set_state(){
    if [ $_domains -eq 0 ]; then
        mgmt_cli -r true set ha-state new-state ${_state}
    else
        mdsdomains
        for _domain in ${DOMAINS[@]}; do
            mgmt_cli -d ${_domain} -r true set ha-state new-state ${_state}
        done
    fi
}

function get_state(){
   mgmt_cli -r true show ha-state -f json | jq -r '.domains[]|[.name,.servers[0]]'
}

while :
do
    clear
    echo " "
    echo "-------------------------------------"
    echo "[1] High-Availability Status"
    echo "[2] Set all domains ACTIVE"
    echo "[3] Set all domains STANDBY"
    echo "[4] Exit"
    echo "====================================="
    echo "Enter your menu choice [1-4]: "
    read choice

    case "$choice" in

        1)  get_state
            echo "Press ENTER to continue"
            read;;

        2) _state="active"
           set_state
           get_state
           echo "Press ENTER to continue"
           read;;

        3) _state="standby"
           set_state
           get_state
           echo "Press ENTER to continue"
           read;;

        4) exit 0;;
        *) echo "Invalid choice";
           echo "Press ENTER to continue"
           read;;
    esac
done