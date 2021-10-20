#!/bin/bash
# This script will export the proxy settings version from each checkpoint-host

_domains=`mgmt_cli -r true show domains -f json | jq -r .total`

function mdsdomains(){
    DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
    DOMAINS+=("Global")
}

function dump_proxy_settings(){
        mdsdomains
        echo -e "Domain\tHost\tEnabled\tHost\tPort"
        for _domain in ${DOMAINS[@]};
        do
            mgmt_cli -r true -d ${_domain} login > id.txt
            _names=(`mgmt_cli -s id.txt -d ${_domain} show gateways-and-servers -f json | jq -r '.objects[]|select(.type=="checkpoint-host")|.name'`)
            _uids=(`mgmt_cli -s id.txt -d ${_domain} show gateways-and-servers -f json | jq -r '.objects[]|select(.type=="checkpoint-host")|.uid'`)
            _uidcount="${#_uids[@]}"
            _counter=0
            while [[ ${_counter} -lt ${_uidcount} ]]
            do
                for _uid in ${_uids[@]};
                do
                    values=(`mgmt_cli -s id.txt -d ${_domain} show generic-object uid ${_uid} -f json | jq -r "[.proxyEnableOverrideSettings,.proxyOverrideSettings.proxyAddress,.proxyOverrideSettings.proxyPort]|@csv" | tr ',' ' '`)
                    #mgmt_cli -s id.txt -d ${_domain} show generic-object uid ${_uid} -f json | jq -r "[.proxyEnableOverrideSettings,.proxyOverrideSettings.proxyAddress,.proxyOverrideSettings.proxyPort]"
                    if [ ${values[0]} == "true" ]; then
                            echo -ne "${_domain}\t${_names[${_counter}]}\t${values[0]}\t${values[1]}\t${values[2]}\n"
                    else
                            echo -ne "${_domain}\t${_names[${_counter}]}\t${values[0]}\n"
                    fi
                    let _counter++
                done
            done
        done
}

dump_proxy_settings