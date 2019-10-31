import os
import sys
import json
import requests
from web3 import Web3
from solcx import install_solc
from solcx import get_solc_version, set_solc_version, compile_files


#Connecting to node
endpoint = "http://127.0.0.1:8545"
w3 = Web3(Web3.HTTPProvider(endpoint, request_kwargs={'timeout': 60}))

if (not w3.isConnected()):
    print("Couldn't connect to node, exiting")
    sys.exit(1)


# # # # # # # # # # # #
# PREPARE CONTRACTS
# # # # # # # # # # # #

with open('./deployedAddresses.json') as json_file:
    deployedAddresses = json.load(json_file)

with open('proofs.json') as json_file:
    proof_data = json.load(json_file)

print(proof_data["proofs"]["level_before_write"]["level"]);

with open('../build/contracts/RevealInstantiator.json') as json_file:
    ri_data = json.load(json_file)

with open('../build/contracts/LoggerMock.json') as json_file:
    logger_mock_data = json.load(json_file)

ri = w3.eth.contract(address=deployedAddresses["ri_address"], abi=ri_data['abi'])
logger_mock = w3.eth.contract(address=deployedAddresses["logger_mock_address"], abi=logger_mock_data['abi'])

print("CONTRACT ADDRESS")
print(deployedAddresses["ri_address"])


# # # # # # # # # # # #
# READ VALUES FROM JSON
# # # # # # # # # # # #

scoreWordPosition = proof_data["proofs"]["score_at_completion"]["proof"]["address"]
logDrivePosition = proof_data["proofs"]["log_before_write"]["proof"]["address"]

scoreDriveLogSize = proof_data["proofs"]["score_at_completion"]["proof"]["log2_size"]
logDriveSize = proof_data["proofs"]["log_before_write"]["proof"]["log2_size"]

templateHash = proof_data["proofs"]["level_after_write"]["proof"]["root_hash"]

logHash = proof_data["proofs"]["log_after_write"]["proof"]["target_hash"]

initialHash = proof_data["proofs"]["log_after_write"]["proof"]["root_hash"]
finalHash = proof_data["proofs"]["score_at_completion"]["proof"]["root_hash"]

score = proof_data["proofs"]["score_at_completion"]["score"]

logDriveSiblings = proof_data["proofs"]["log_after_write"]["proof"]["sibling_hashes"][::-1]
scoreDriveSiblings = proof_data["proofs"]["score_at_completion"]["proof"]["sibling_hashes"][::-1]

print("SCORE WORD POSITION")
print(scoreWordPosition)
print("LOG DRIVE POSITION")
print(logDrivePosition)
print("LOG DRIVE SIZE")
print(logDriveSize)
print("SCORE DRIVE SIZE")
print(scoreDriveLogSize)

# # # # # # # # # # # # # # # # #
# INSTANTIATE REVEAL INSTANTIATOR
# # # # # # # # # # # # # # # # #
tx_hash = ri.functions.instantiate(50, 50, scoreWordPosition, logDrivePosition, scoreDriveLogSize, logDriveSize, templateHash).transact({'from': w3.eth.coinbase, 'gas': 6283185})

tx_receipt = w3.eth.waitForTransactionReceipt(tx_hash)

print(tx_receipt)

# # # # # # # # # # # # # # # # #
# COMMIT PHASE
# # # # # # # # # # # # # # # # #
commit_tx_hash = ri.functions.commit(0, logHash).transact({'from': w3.eth.coinbase, 'gas': 6283185})

print(commit_tx_hash)

commit_tx_receipt = w3.eth.waitForTransactionReceipt(commit_tx_hash)

print(commit_tx_receipt)

ri_filter = ri.events.logCommited.createFilter(fromBlock='latest')
ri_index = ri_filter.get_all_entries()[0]['args']['index']
ri_logHash = ri_filter.get_all_entries()[0]['args']['logHash']
print(ri_index)
print(ri_logHash)

# # # # # # # # # # # # # # # # #
# REVEAL PHASE
# # # # # # # # # # # # # # # # #

# ADVANCE TIME SO COMMIT PHASE IS OVER
# TO-DO: make 51 a param compatible to the instantiate values
method = "evm_increaseTime"
timeToAdvance = 51
w3.provider.make_request(method, timeToAdvance);

# ADD LOG_HASH TO LOGGER MOCK
logger_mock_tx_hash = logger_mock.functions.mockAddHashWithoutVerification(logHash).transact({'from': w3.eth.coinbase, 'gas': 6283185})

logger_mock_tx_receipt = w3.eth.waitForTransactionReceipt(logger_mock_tx_hash )
print("LOGGER MOCK RECEIPT")
print(logger_mock_tx_receipt)

# REVEAL LOG
reveal_tx_hash = ri.functions.reveal(0, score, finalHash, logHash, logDriveSiblings, scoreDriveSiblings).transact({'from': w3.eth.coinbase, 'gas': 6283185})


reveal_tx_receipt = w3.eth.waitForTransactionReceipt(reveal_tx_hash )
print("REVEAL RECEIPT")
print(reveal_tx_receipt)




