var VGMock = artifacts.require("./VGMock.sol");
var MatchInstantiator = artifacts.require("./MatchInstantiator.sol");
var MatchManagerInstantiator = artifacts.require("./MatchManagerInstantiator.sol");
var RevealMock = artifacts.require("./RevealMock.sol");

module.exports = function(deployer) {
    deployer.deploy(VGMock).then(function() {
        deployer.deploy(MatchInstantiator, VGMock.address).then(function(){
            deployer.deploy(MatchManagerInstantiator, MatchInstantiator.address)
        });
    });
    deployer.deploy(RevealMock);
};

