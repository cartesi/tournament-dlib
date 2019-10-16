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
import yaml
import glob
import argparse
import docker

# cartesi files
BLOCKCHAIN_DIR = "blockchain_files/"
WALLETS_FILE = "wallets.yaml"
WALLETS_FILE_PATH = BLOCKCHAIN_DIR + WALLETS_FILE
BASE_CONFIG_FILE = "cartesi_dapp_config.yaml"

IS_BUILD = False
IS_CLEAN = False
IS_RUN = False

def get_args():
    parser = argparse.ArgumentParser(description='Simple helper program to manage the docker service, including building images and running containers')
    parser.add_argument('--build', '-b', dest='is_build', action='store_true', default=False, help="Build docker images (Default: False)")
    parser.add_argument('--clean', '-c', dest='is_clean', action='store_true', default=False, help="Clean docker containers (Default: False)")
    parser.add_argument('--run', '-r', dest='is_run', action='store_true', default=False, help="Run docker containers (Default: False)")


    args = parser.parse_args()

    global IS_BUILD
    global IS_CLEAN
    global IS_RUN

    if (args.is_build):
        IS_BUILD = True

    if (args.is_clean):
        IS_CLEAN = True

    if (args.is_run):
        IS_RUN = True

def get_cartesi_network(docker_client):

    networks=docker_client.networks.list(names=["cartesi-network"])
    if len(networks) > 0:
        return networks[0]
    else:
        return docker_client.networks.create(name="cartesi-network", driver="bridge")

def clean():
    client = docker.from_env()
    containers = client.containers.list(filters={"name": "tournament"})
    for container in containers:
        print("Removing {}...".format(container.name))
        container.remove(force=True)


def run_blockchain():

    cwd = os.getcwd()
    client = docker.from_env()

    cartesi_network = get_cartesi_network(client)

    print("starting blockchain...")
    container = client.containers.create("cartesi/image-tournament-blockchain-base",
        #detach=True
        auto_remove=True,
        tty=True,
        name="tournament-blockchain-base")
    cartesi_network.connect(container)
    container.start()

    print("done!")

def run_dispatcher():

    cwd = os.getcwd()
    client = docker.from_env()
    number_of_dispatchers = 0
    
    cartesi_network = get_cartesi_network(client)
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
            print("starting dispatcher {}...".format(idx))
            bash_cmd = 'bash -c "export RUST_LOG=dispatcher=trace,transaction=trace,configuration=trace,utils=trace,state=trace,compute=trace,hasher=trace,dappmock=trace,match=trace,matchmanager=trace,revealmock=trace && export CARTESI_CONCERN_KEY={} && mkdir -p /opt/cartesi/working_path && cat /opt/cartesi/dispatcher_config_{}.yaml && cargo run -- --config_path /opt/cartesi/dispatcher_config_{}.yaml --working_path /opt/cartesi/working_path"'.format(account["key"], idx, idx)
            container = client.containers.create("cartesi/image-tournament-test",
                #detach=True
                auto_remove=True,
                command=bash_cmd,
                tty=True,
                name="tournament-test-{}".format(idx),
                volumes=volumes)
            cartesi_network.connect(container)
            container.start()

    print("done!")

get_args()

if IS_CLEAN:
    clean()

if IS_RUN:
    run_blockchain()
    run_dispatcher()