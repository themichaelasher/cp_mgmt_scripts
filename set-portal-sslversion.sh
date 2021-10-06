#!/bin/bash
#
# This script will set the minimum TLS version for the platform portals. 
# The default value is TLS_1.0 (through R81) and many times needs to be changed to TLS1.2
# See sk109256 for more information
# - https://supportcenter.checkpoint.com/supportcenter/portal?eventSubmit_doGoviewsolutiondetails=&solutionid=sk109256
#
# This uses the undocumented generic-object API functionality, so you should test in a lab first. 

_domains=`mgmt_cli -r true show domains -f json | jq -r .total`

function mdsdomains(){
    DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
    DOMAINS+=("Global")
}

function dump_portal_tls_versions(){
        echo -ne "\n"
        mdsdomains
        echo -ne "DOMAIN\tMINSSL\tMAXSSL\n"
        for _domain in ${DOMAINS[@]}; do
                mgmt_cli -r true -d ${_domain} login > id.txt
                _fwpropsuid=`mgmt_cli -s id.txt show-generic-objects name firewall_properties -f json | jq -r '.objects[0].uid'`
                _sslversions=(`mgmt_cli -s id.txt show generic-object uid ${_fwpropsuid} -f json | jq -r '(.snxSslMinVer,.snxSslMaxVer)'|tr '\n' ' '`)
                echo -ne "${_domain}\t${_sslversions[0]}\t${_sslversions[1]}\n"
                mgmt_cli -s id.txt logout 2>1 >> /dev/null
        done
}

function set_portal_tls_minver(){
        echo -ne "\n"
        mdsdomains
        for _domain in ${DOMAINS[@]}; do
                mgmt_cli -r true -d ${_domain} login > id.txt
                _fwpropsuid=`mgmt_cli -s id.txt show-generic-objects name firewall_properties -f json | jq -r '.objects[0].uid'`
                echo "${_domain}: Setting snxSslMinVer to ${_minver}"
                mgmt_cli -s id.txt set generic-object uid ${_fwpropsuid} snxSslMinVer ${_minver}
                echo "${_domain}: Publishing changes and logging out."
                mgmt_cli -s id.txt publish 2>1 >> /dev/null
                mgmt_cli -s id.txt logout 2>1 >> /dev/null
        done
}

while :
do
    clear
    echo " "
    echo "-----------------------------------------"
    echo "[1] Show Portal TLS Versions"
    echo "[2] Set Portal TLS minver to TLS 1.2"
    echo "[3] Revert Portal TLS minver to TLS 1.0"
    echo "[4] Exit"
    echo "========================================="
    echo -n "Enter your menu choice [1-4]: "
    read choice

    case "$choice" in

        1)  dump_portal_tls_versions
            echo -ne "\nPress ENTER to continue"
            read;;

        2) _minver="TLS1_2"
           set_portal_tls_minver
           dump_portal_tls_versions
           echo -ne "\nPress ENTER to continue"
           read;;

        3) _minver="TLS1_0"
           set_portal_tls_minver
           dump_portal_tls_versions
           echo -ne "\nPress ENTER to continue"
           read;;

        4) echo -ne '\n'; exit 0;;
        *) echo "Invalid choice";
           echo "Press ENTER to continue"
           read;;
    esac
done