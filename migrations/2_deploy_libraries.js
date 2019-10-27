var RevealInstantiator = artifacts.require("./RevealInstantiator.sol");
var MatchManagerInstantiator = artifacts.require("./MatchManagerInstantiator.sol");
var MatchInstantiator = artifacts.require("./MatchInstantiator.sol");

var VGMock = artifacts.require("./VGMock.sol");
var RevealMock = artifacts.require("./RevealMock.sol");
var DAppMock = artifacts.require("./DAppMock.sol");

module.exports = function(deployer, network, accounts) {

    deployer.then(async () => {
        await deployer.deploy(VGMock);
        await deployer.deploy(MatchInstantiator, VGMock.address);
        await deployer.deploy(MatchManagerInstantiator, MatchInstantiator.address);
        await deployer.deploy(RevealInstantiator);

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
    });

};

