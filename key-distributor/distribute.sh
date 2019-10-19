#!/bin/sh
echo "Distributing keys from $1 into /key-{i} volumes starting with /key-0"
cat $1 | jq -r '.private_keys | to_entries[] | .key' | awk '{print "echo " $1 " > /key-" (NR-1) "/account" | "/bin/ash" }'
cat $1 | jq -r '.private_keys | to_entries[] | .value' | awk '{print "echo " $1 " > /key-" (NR-1) "/private_key" | "/bin/ash" }'
