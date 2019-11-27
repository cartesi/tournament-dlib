#!/bin/sh

export CARTESI_CONCERN_KEY=`cat /opt/cartesi/etc/keys/private_key`
export ACCOUNT_ADDRESS=`cat /opt/cartesi/etc/keys/account`
echo "Creating configuration file at /opt/cartesi/etc/dispatcher/config.yaml with account ${ACCOUNT_ADDRESS}"
envsubst < /opt/cartesi/etc/dispatcher/config-template.yaml > /opt/cartesi/etc/dispatcher/config.yaml
cat /opt/cartesi/etc/dispatcher/config.yaml

/opt/cartesi/bin/dispatcher --config_path /opt/cartesi/etc/dispatcher/config.yaml --working_path /opt/cartesi/srv/dispatcher
