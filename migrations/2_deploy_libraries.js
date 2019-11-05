require('dotenv').config();
const fs = require('fs');


var RevealInstantiator = artifacts.require("./RevealInstantiator.sol");
var BitsManipulationLibrary = artifacts.require("./BitsManipulationLibrary.sol");
var MatchManagerInstantiator = artifacts.require("./MatchManagerInstantiator.sol");
var MatchInstantiator = artifacts.require("./MatchInstantiator.sol");
var Logger = artifacts.require("../logger-dlib/contracts/Logger.sol");

var LoggerMock = artifacts.require("../test/LoggerMock.sol");

var VGMock = artifacts.require("../test/VGMock.sol");
var RevealMock = artifacts.require("../test/RevealMock.sol");
var DAppMock = artifacts.require("../test/DAppMock.sol");

module.exports = function(deployer, network, accounts) {

    deployer.then(async () => {
        await deployer.deploy(BitsManipulationLibrary);
        await deployer.link(BitsManipulationLibrary, RevealInstantiator);

        await deployer.deploy(Logger);
        await deployer.deploy(VGMock);
        await deployer.deploy(LoggerMock);

        await deployer.deploy(MatchInstantiator, VGMock.address);
        await deployer.deploy(MatchManagerInstantiator, MatchInstantiator.address);

        // TO-DO: Should deploy with real Logger, not LoggerMock
        //await deployer.deploy(RevealInstantiator, Logger.address);

        // THIS IS JUST FOR TESTING PURPOSES
        await deployer.deploy(RevealInstantiator, LoggerMock.address);

        // add main "player" values here before adding other accounts
        var playerAddresses = [accounts[0]];
        var scores = [100];
        var finalHashes = ["0x01"];

        for (var i = 1; i < accounts.length; i++) {
            playerAddresses.push(accounts[i]);
            scores.push(i * 20);
            finalHashes.push("0x00");
        }

        await deployer.deploy(RevealMock, MatchManagerInstantiator.address);
        await deployer.deploy(DAppMock, RevealMock.address, playerAddresses, scores, finalHashes);

        // TO-DO: Shouldnt be logger_mock, should be actual logger
        // Write address to file
        let addr_json = "{\"ri_address\":\"" + RevealInstantiator.address + "\", \"logger_mock_address\":\"" + LoggerMock.address + "\"}";

        fs.writeFile('../test/deployedAddresses.json', addr_json, (err) => {
          if (err) console.log("couldnt write to file");
        });

    });

};

