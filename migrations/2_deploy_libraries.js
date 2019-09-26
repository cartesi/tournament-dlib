var VGMock = artifacts.require("./VGMock.sol");
var MatchInstantiator = artifacts.require("./MatchInstantiator.sol");
var MatchManagerInstantiator = artifacts.require("./MatchManagerInstantiator.sol");
var RevealMock = artifacts.require("./RevealMock.sol");
var DAppMock = artifacts.require("./DAppMock.sol");

module.exports = function(deployer, network, accounts) {
    deployer.deploy(VGMock).then(function() {
        deployer.deploy(MatchInstantiator, VGMock.address).then(function(){
            deployer.deploy(MatchManagerInstantiator, MatchInstantiator.address)
        });
    });

    // add main "player" values here before adding other accounts
    var playerAddresses = [accounts[0]];
    var scores = [100];
    var finalHashes = ["0x01"];

    for (var i = 1; i < 9; i++) {
        playerAddresses.push(accounts[i]);
        scores.push(i * 20);
        finalHashes.push("0x00");
    }

    deployer.deploy(RevealMock).then(function() {
        deployer.deploy(DAppMock, RevealMock.address, playerAddresses, scores, finalHashes);
    });
};

