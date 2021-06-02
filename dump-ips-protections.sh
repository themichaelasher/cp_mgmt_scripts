#!/bin/bash
#
# This will cycle through the IPS protections and output them to CSV. 
# For MDS, simply adjust the mgmt_cli login command by adding -d <domain|Global> command

mgmt_cli -r true login > session.id


PKGVER=`mgmt_cli -s session.id show ips-status -f json | jq -r '."installed-version"'`
TOTAL=`mgmt_cli -s session.id show threat-protections details-level full  -f json | jq -r '.total'`

echo "uid,name,severity,release-date,update-date,Confidence, Performance Impact, follow-up" > available-protections.${PKGVER}.csv
i=0
while [[ $i -lt ${TOTAL} ]];
do
  mgmt_cli -s session.id show threat-protections details-level full  -f json limit 500 offset ${i} | jq -r '.protections[]|[.uid,.name,.severity,."release-date",."update-date",."confidence-level",."performance-impact",."follow-up"]|@csv' >> available-protections.${PKGVER}.csv
  let "i = $i + 500"
done

