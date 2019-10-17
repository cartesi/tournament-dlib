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
    containers = client.containers.list(all=True, filters={"name": "tournament"})
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
    blockchain_container = client.containers.get("tournament-blockchain-base")

    with open(BASE_CONFIG_FILE, 'r') as base_file:
        base = yaml.safe_load(base_file)
        number_of_dispatchers = base["dispatcher_base"]["number_of_dispatchers"]

    for idx in range(number_of_dispatchers):
        # start dispatcher
        print("starting dispatcher {}...".format(idx))
        dispatcher = client.containers.create("cartesi/image-tournament-test",
            #detach=True
            auto_remove=True,
            tty=True,
            name="tournament-test-{}".format(idx))
        cartesi_network.connect(dispatcher)

        key_bits, stat = blockchain_container.get_archive("/opt/cartesi/wallet_{}/cartesi_concern_key".format(idx))
        config_bits, stat = blockchain_container.get_archive("/opt/cartesi/wallet_{}/dispatcher_config.yaml".format(idx))
        dispatcher.put_archive("/opt/cartesi/wallet", key_bits)
        dispatcher.put_archive("/opt/cartesi/wallet", config_bits)

        dispatcher.start()

    print("done!")

get_args()

if IS_CLEAN:
    clean()

if IS_RUN:
    run_blockchain()
    run_dispatcher()