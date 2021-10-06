#!/bin/bash
# This script will export the TLS version from each domain. 

_domains=`mgmt_cli -r true show domains -f json | jq -r .total`

function mdsdomains(){
    DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
    DOMAINS+=("Global")
}

function dump_portal_tls_versions(){
        mdsdomains
        echo -ne "DOMAIN\tMINSSL\tMAXSSL\n"
        for _domain in ${DOMAINS[@]}; do
                mgmt_cli -r true -d ${_domain} login > id.txt
                _fwpropsuid=`mgmt_cli -s id.txt show-generic-objects name firewall_properties -f json | jq -r '.objects[0].uid'`
                _sslversions=(`mgmt_cli -s id.txt show generic-object uid ${_fwpropsuid} -f json | jq -r '(.snxSslMinVer,.snxSslMaxVer)'|tr '\n' ' '`)
                
                echo -ne "${_domain}\t${_sslversions[0]}\t${_sslversions[1]}\n"
        done
}

dump_portal_tls_versions