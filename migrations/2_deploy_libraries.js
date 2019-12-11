const contract = require("@truffle/contract");
const BitsManipulationLibrary = contract(require("@cartesi/util/build/contracts/BitsManipulationLibrary.json"));
const VGInstantiator = contract(require("@cartesi/arbitration/build/contracts/VGInstantiator.json"));
const Logger = contract(require("@cartesi/logger/build/contracts/Logger.json"));

const RevealInstantiator = artifacts.require("RevealInstantiator");
const MatchManagerInstantiator = artifacts.require("MatchManagerInstantiator");
const MatchInstantiator = artifacts.require("MatchInstantiator");

module.exports = function(deployer) {

    deployer.then(async () => {
        BitsManipulationLibrary.setNetwork(deployer.network_id);
        VGInstantiator.setNetwork(deployer.network_id);
        Logger.setNetwork(deployer.network_id);

        await deployer.link(BitsManipulationLibrary, RevealInstantiator);
        await deployer.deploy(MatchInstantiator, VGInstantiator.address);
        await deployer.deploy(MatchManagerInstantiator, MatchInstantiator.address);
        await deployer.deploy(RevealInstantiator, Logger.address);
    });

};
