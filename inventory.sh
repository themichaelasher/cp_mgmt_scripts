#!/bin/bash

OUTPUTDIR="/home/admin/inventory"
ID="${OUTPUTDIR}/session.id"

if [! -x ${OUTPUTDIR} ]; then
        mkdir ${OUTPUTDIR}
fi

cd ${OUTPUTDIR}
# Fetch domain count
_domains=`mgmt_cli -r true -d MDS show domains -f json | jq -r .total`

# This will run the ifconfig command against the gateway using the run-script API command.
# When Gaia-API is 100% available, it wil be faster to query accessible gateways directly.

function getdata(){
        ${MGMTCMD} show gateways-and-servers -f json details-level full | jq -r '.objects[]|select(.type =="CpmiClusterMember" or .type=="simple-gateway" or .type=="CpmiVsxClusterMember")|.name' > gws.info
        for _gw in `cat gws.info`; do
                echo "${_gw}, `${MGMTCMD} run-script script-name "inventory check" script "ifconfig -a" -f json  targets ${_gw} 2>/dev/null | jq -r '.tasks[]|."task-details"[]|.responseMessage' | base64 -d  | grep HWaddr | awk '{print $1,",",$5}' | tr '\n' ',' `" >> ${EXPORTFILE}
        done
        ${MGMTCMD} logout 2>/dev/null 1>/dev/null
}

# Not necessarily required as a function, but just in case additional items are needed.

function mdsdomains(){
        DOMAINS="`${MGMTCMD} show domains -f json | jq -r '.objects[]|.name' | tr '\n' ' '`"
}


if [ $_domains -eq 1 ]; then
        EXPORTFILE="${OUTPUTDIR}/inventory.csv"
        mgmt_cli -r true login > ${ID}
        MGMTCMD="mgmt_cli -s ${ID}"
        getdata
        mgmt_cli -s ${ID} logout 2>/dev/null 1>/dev/null
else
        mgmt_cli -r true -d MDS login > ${ID}
        MGMTCMD="mgmt_cli -s ${ID}"
        mdsdomains
        for _domain in ${DOMAINS[@]}; do
                echo "Domain: ${_domain}"
                EXPORTFILE="${OUTPUTDIR}/${_domain}.inventory.csv"
                echo -ne "Exporting ${_domain} information:"
                mgmt_cli -d ${_domain} -r true login > ${_domain}.id
                MGMTCMD="mgmt_cli -s ${_domain}.id"
                getdata
                rm ${_domain}.id
                echo -en " completed\n"
        done
        cat *.csv > inventory.csv
        mgmt_cli -s ${ID} logout 2>/dev/null 1>/dev/null
        rm *.inventory.csv
fi


# Cleanup
rm ${ID}
rm gws.info


echo "Script Complete"
