users=`cat ./blockchain_files/wallets.yaml | grep address | awk -F\' '{print $2}'`
keys=`cat ./blockchain_files/wallets.yaml | grep key | awk '{print $2}'`
count=0
for user in $users; do
    mkdir -p wallet_${count}
    python3 dispatcher_config_generator.py -ua $user -o wallet_${count}/dispatcher_config.yaml
    count=$((count + 1))
done

count=0
for key in $keys; do
    mkdir -p wallet_${count}
    echo "export CARTESI_CONCERN_KEY=$key" > wallet_${count}/cartesi_concern_key
    count=$((count + 1))
done