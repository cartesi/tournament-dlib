# usage:
#    jq -n 'inputs | { (input_filename) : . } ' *.json | jq -s -f dispatcher_config.jq --arg key mykey
add |
{
    concerns: [
        {
            abi: "/opt/cartesi/blockchain/contracts/MatchInstantiator.json",
            contract_address: (.["MatchInstantiator.json"].networks | to_entries[0].value.address),
            user_address: $key
        },
        {
            abi: "/opt/cartesi/blockchain/contracts/MatchManagerInstantiator.json",
            contract_address: (.["MatchManagerInstantiator.json"].networks | to_entries[0].value.address),
            user_address: $key
        },
        {
            abi: "/opt/cartesi/blockchain/contracts/RevealMock.json",
            contract_address: (.["RevealMock.json"].networks | to_entries[0].value.address),
            user_address: $key
        },
        {
            abi: "/opt/cartesi/blockchain/contracts/VGMock.json",
            contract_address: (.["VGMock.json"].networks | to_entries[0].value.address),
            user_address: $key
        }
    ],
    main_concern: {
        abi: "/opt/cartesi/blockchain/contracts/DAppMock.json",
        contract_address: (.["DAppMock.json"].networks | to_entries[0].value.address),
        user_address: $key
    },
    confirmations: 0,
    max_delay: 500,
    query_port: 3001,
    services: [{
        name: "emulator",
        transport: {
           address: "machine-manager",
           port: 50051
        }
    }],
    testing: true,
    url: "http://ganache:8545",
    warn_delay: 30
}
