#!/bin/ash
# Copyright 2020 Ciena Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

trap "echo 'exiting on trap'; exit" SIGHUP SIGINT SIGTERM

python3 -m http.server -d /data 8080 2>&1 > /tmp/http.log &

mkdir -p /data/subscribers /data/profiles
while true; do
    INSTANCES=$(/usr/local/bin/kubectl -s https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT get -l app=bbsim --all-namespaces svc -o json | jq -r '.items[].metadata | .name+"."+.namespace+".svc:50074"')
    rm -rf /tmp/raw-subscribers /tmp/raw-profiles
    for INST in $INSTANCES; do
        curl --connect-timeout 3 --max-time 5 -sSL $INST/v2/static 2>"/tmp/last-errors.$INST" > /tmp/raw-data
        cat /tmp/raw-data | jq .sadis.entries | jq '.[]' >> /tmp/raw-subscribers
        cat /tmp/raw-data | jq .bandwidthprofile.entries | jq '.[]' >> /tmp/raw-profiles
    done
    cat /tmp/raw-subscribers | jq --slurp '. |unique' > /tmp/subscribers
    cat /tmp/raw-profiles | jq --slurp '. |unique' > /tmp/profiles

    # Create/update records
    SUB_ADD_COUNT=0
    for i in $(cat /tmp/subscribers | jq -c .[]); do
        ID=$(echo $i | jq -r .id)
        echo "UPDATING: $ID"
        SUB_ADD_COUNT=$((SUB_ADD_COUNT+1))
        echo $i | jq . >  /data/subscribers/$ID
    done

    PRO_ADD_COUNT=0
    for i in $(cat /tmp/profiles | jq -c .[]); do
        ID=$(echo $i | jq -r .id)
        echo "UPDATING: $ID"
        PRO_ADD_COUNT=$((PRO_ADD_COUNT+1))
        echo $i | jq . >  /data/profiles/$ID
    done

    # Delete records no longer valid
    SUB_DEL_COUNT=0
    ALL=":$(cat /tmp/subscribers | jq -r .[].id | tr '\n' ':')"
    for d in $(ls -1 /data/subscribers); do
        FOUND=$(echo "$ALL" | grep -c ":$d:")
        if [ $FOUND -eq 0 ]; then
            echo "REMOVING: $d"
            SUB_DEL_COUNT=$((SUB_DEL_COUNT+1))
            rm -rf /data/subscribers/$d
        fi
    done

    PRO_DEL_COUNT=0
    ALL=":$(cat /tmp/profiles | jq -r .[].id | tr '\n' ':')"
    for d in $(ls -1 /data/profiles); do
        FOUND=$(echo "$ALL" | grep -c ":$d:")
        if [ $FOUND -eq 0 ]; then
            echo "REMOVING: $d"
            PRO_DEL_COUNT=$((PRO_DEL_COUNT+1))
            rm -rf /data/profiles/$d
        fi
    done

    echo "SUMMARY: $(ls -1 /data/subscribers /data/profiles | wc -l) RECORD(s), +$SUB_ADD_COUNT/-$SUB_DEL_COUNT SUSCRIBER RECORD(s), +$PRO_ADD_COUNT/-$PRO_DEL_COUNT PROFILE RECORD(s)"
    echo "====="
    sleep 5
done

