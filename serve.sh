#!/bin/ash
# shellcheck shell=ash
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

trap "echo 'exiting on trap'; exit" HUP INT TERM

parseDuration() {
    local DUR RESULT TERMS VALUE UNIT
    DUR=$1
    RESULT=0
    TERMS=$(echo "$DUR" | sed -Ee 's/([sSmMhHdD])/\1 /g' -e 's/,$//g')
    for TERM in $TERMS; do
       VALUE=$(echo "$TERM" | sed -Ee 's/([0-9]+)[sSmMhHdD]/\1/')
       UNIT=$(echo "$TERM" | sed -Ee 's/[0-9]+([sSmMhHdD])/\1/')
       case $UNIT in
          s|S)
             RESULT=$((RESULT + VALUE)) ;;
          m|M)
             RESULT=$((RESULT + (VALUE * 60))) ;;
          h|H)
             RESULT=$((RESULT + (VALUE * 3600))) ;;
          d|D)
             RESULT=$((RESULT + (VALUE * 86400))) ;;
          *) ;;
       esac
    done
    echo "$RESULT"
}

SLEEP_TIME=${SLEEP_TIME:-5s}
SLEEP_TIME_SECONDS=$(parseDuration "$SLEEP_TIME")
DATA_DIR="$(pwd)"

mkdir -p "$DATA_DIR/subscribers" "$DATA_DIR/profiles"
python3 -m http.server 8080 >/tmp/http.log 2>&1 &

while true; do
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) UPDATES"
    INSTANCES=$(/usr/local/bin/kubectl -s "https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_PORT_443_TCP_PORT" get -l app=bbsim --all-namespaces svc -o json | jq -r '.items[].metadata | .name+"."+.namespace+".svc:50074"')
    rm -rf /tmp/raw-subscribers /tmp/raw-profiles
    touch /tmp/raw-subscribers /tmp/raw-profiles
    for INST in $INSTANCES; do
        curl --connect-timeout 3 --max-time 5 -sSL "$INST/v2/static" 2>"/tmp/last-errors.$INST" > /tmp/raw-data
        jq .sadis.entries < /tmp/raw-data | jq '.[]' >> /tmp/raw-subscribers
        jq .bandwidthprofile.entries < /tmp/raw-data | jq '.[]' >> /tmp/raw-profiles
    done
    jq --slurp '. |unique' < /tmp/raw-subscribers > /tmp/subscribers
    jq --slurp '. |unique' < /tmp/raw-profiles > /tmp/profiles

    # Create/update records
    SUB_ADD_COUNT=0
    for i in $(jq -c '.[]' < /tmp/subscribers); do
        ID=$(echo "$i" | jq -r .id)
        echo "$i" | jq . > /tmp/work
        test -f "$DATA_DIR/subscribers/$ID" && diff /tmp/work "$DATA_DIR/subscribers/$ID" >/dev/null 2>&1
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            echo "    UPDATING SUBSCRIBER: $ID"
            SUB_ADD_COUNT=$((SUB_ADD_COUNT+1))
            cp /tmp/work "$DATA_DIR/subscribers/$ID"
        fi
    done

    PRO_ADD_COUNT=0
    for i in $(jq -c '.[]' < /tmp/profiles); do
        ID=$(echo "$i" | jq -r .id)
        echo "$i" | jq . >  /tmp/work
        test -f "$DATA_DIR/profiles/$ID" && diff /tmp/work "$DATA_DIR/profiles/$ID" >/dev/null 2>&1
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            echo "    UPDATING PROFILE: $ID"
            PRO_ADD_COUNT=$((PRO_ADD_COUNT+1))
            cp /tmp/work "$DATA_DIR/profiles/$ID"
        fi
    done

    # Delete records no longer valid
    SUB_DEL_COUNT=0
    ALL=":$(jq -r '.[].id' < /tmp/subscribers  | tr '\n' ':')"
    for d in "$DATA_DIR"/subscribers/*; do
        d="$(basename "$d")"
        FOUND=$(echo "$ALL" | grep -c ":$d:")
        if [ "$FOUND" -eq 0 ]; then
            echo "    REMOVING SUBSCRIBER: $d"
            SUB_DEL_COUNT=$((SUB_DEL_COUNT+1))
            rm -rf "$DATA_DIR/subscribers/$d"
        fi
    done

    PRO_DEL_COUNT=0
    ALL=":$(jq -r '.[].id' < /tmp/profiles | tr '\n' ':')"
    for d in "$DATA_DIR"/profiles/*; do
        d="$(basename "$d")"
        FOUND=$(echo "$ALL" | grep -c ":$d:")
        if [ "$FOUND" -eq 0 ]; then
            echo "    REMOVING PROFILE: $d"
            PRO_DEL_COUNT=$((PRO_DEL_COUNT+1))
            rm -rf "$DATA_DIR/profiles/$d"
        fi
    done

    echo "    SUMMARY: $(find "$DATA_DIR/subscribers" -type f -not -name "\.*" | wc -l)/+$SUB_ADD_COUNT/-$SUB_DEL_COUNT SUSCRIBER RECORD(s), $(find "$DATA_DIR/profiles" -type f -not -name "\.*" | wc -l)/+$PRO_ADD_COUNT/-$PRO_DEL_COUNT PROFILE RECORD(s)"
    echo "====="
    sleep "$SLEEP_TIME_SECONDS"
done

