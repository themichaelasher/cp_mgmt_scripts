#!/bin/bash

# Dump IPS Protections from Global and additional domains.
# Untested on stand-alone, but I don't see why it wouldn't work. 

_domains=`mgmt_cli -r true show domains -f json | jq -r .total`

function mdsdomains(){
    DOMAINS=(`mgmt_cli -r true show domains -f json | jq -r '.objects[]|.name'`)
    # Add global domain as it does not show off in the show domains list.
    DOMAINS+=("Global")
}

function dumpdata(){
 echo "Exporting: ${_domain}"
 echo "name,severity,release-date,update-date,Confidence, Performance Impact" > ${_domain}.available-protections.${PKGVER}.csv
 i=0
 while [[ $i -lt ${TOTAL} ]];
 do
        mgmt_cli -s id.txt show threat-protections details-level full  -f json limit 500 offset ${i} | jq -r '.protections[]|[.name,.severity,."release-date",."update-date",."confidence-level",."performance-impact"]|@csv' >> ${_domain}.available-protections.${PKGVER}.csv
        let "i = $i + 500"
 done
}

function dump_ips_info(){
    if [ $_domains -eq 0 ]; then
        mgmt_cli -r true login > id.txt
        PKGVER=`mgmt_cli -s id.txt show ips-status -f json | jq -r '."installed-version"'`
        TOTAL=`mgmt_cli -s id.txt show threat-protections details-level full  -f json | jq -r '.total'`
        # Set "fake" domain for SMS
        _domain="SMS"
        dumpdata
        mgmt_cli -s id.txt logout
        rm id.txt
    else
        mdsdomains
        for _domain in ${DOMAINS[@]}; do
           mgmt_cli -r true -d ${_domain} login > id.txt
           PKGVER=`mgmt_cli -s id.txt show ips-status -f json | jq -r '."installed-version"'`
           TOTAL=`mgmt_cli -s id.txt show threat-protections details-level full  -f json | jq -r '.total'`
           dumpdata
           mgmt_cli -s id.txt logout
           rm id.txt
        done
    fi
}

dump_ips_info      
