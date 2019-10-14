# Copyright 2019 Cartesi Pte. Ltd.

# Licensed under the Apache License, Version 2.0 (the "License"); you may not use
# this file except in compliance with the License. You may obtain a copy of the
# License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.

import os
import sys
import json
import yaml
import time
import glob
import argparse
import subprocess
import docker

# cartesi files
BLOCKCHAIN_DIR = "blockchain_files/"
WALLETS_FILE = "wallets.yaml"
WALLETS_FILE_PATH = BLOCKCHAIN_DIR + WALLETS_FILE
BASE_CONFIG_FILE = "cartesi_dapp_config.yaml"

def run():

    cwd = os.getcwd()
    client = docker.from_env()
    number_of_dispatchers = 0
    
    networks=client.networks.list(names=["cartesi-network"])
    if len(networks) > 0:
        cartesi_network = networks[0]
    else:
        ipam_pool = docker.types.IPAMPool(
            subnet='172.18.0.0/16',
            gateway='172.18.0.1'
        )
        cartesi_network = client.networks.create(name="cartesi-network", driver="bridge", ipam=ipam_pool)
    volumes={"{}/transferred_files".format(cwd):{"bind":"/opt/cartesi/transferred_files", "mode":"rw"}}

    with open(BASE_CONFIG_FILE, 'r') as base_file:
        base = yaml.safe_load(base_file)
        number_of_dispatchers = base["dispatcher_base"]["number_of_dispatchers"]

    with open(WALLETS_FILE_PATH, 'r') as wallets_file:
        wallets = yaml.safe_load(wallets_file)
        for idx, account in enumerate(wallets):
            if idx >= number_of_dispatchers:
                break
            # start dispatcher
            print("starting dispatcher...")
            bash_cmd = '"bash -c export RUST_LOG=dispatcher=trace,transaction=trace,configuration=trace,utils=trace,state=trace,compute=trace,hasher=trace,dappmock=trace,match=trace,matchmanager=trace,revealmock=trace && export CARTESI_CONCERN_KEY={} && mkdir -p /opt/cartesi/working_path && cat /opt/cartesi/dispatcher_config_{}.yaml && cargo run -- --config_path /opt/cartesi/dispatcher_config_{}.yaml --working_path /opt/cartesi/working_path"'.format(account["key"], idx, idx)
            container = client.containers.create("cartesi/image-tournament-test",
                #detach=True
                #auto_remove=True,
                command="/bin/bash",
                tty=True,
                stdin_open=True,
                name="tournament-test-{}".format(idx),
                volumes=volumes,
                ports={"3001/tcp": ("127.0.0.1", 3001)}
                )
            cartesi_network.connect(container, ipv4_address="172.18.0.{}".format(24 + idx))
            print(bash_cmd)
            container.exec_run(cmd=bash_cmd,
                stdout=True,
                stderr=True,
                stream=True)

    print("done!")

run()