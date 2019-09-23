/// @title Dapp
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "./RevealMock.sol";
import "../../arbitration-dlib/contracts/Decorated.sol";
import "../../arbitration-dlib/contracts/Instantiator.sol";

contract DApp is Decorated, Instantiator{

    RevealMock private rm;
    struct DappCtx {
        uint256 revealIndex;
        mapping(address => bool) playersConcern; //player address to isConcerned
    }

    mapping(uint256 => DappCtx) internal instance;

    function instantiate(
        address[] memory _playerAddresses,
        uint256[] memory _scores,
        bytes32[] memory _finalHashes
    ) public returns (uint256) {
        // this also instantiate match manager
        instance[currentIndex].revealIndex = rm.instantiate(
            0, //commit duration
            0, //reveal duration
            5000, //epoch duration
            200, //match duration
            0, // final time
            "0x00", //inital hash
            address(0) //machine address
        );

        // add user to concern
        for (uint256 i = 0; i < _playerAddresses.length; i++) {
            instance[currentIndex].playersConcern[_playerAddresses[i]] = true;
        }

        // also have to add yourself
        rm.addFakePlayers(instance[currentIndex].revealIndex, _playerAddresses, _scores, _finalHashes);

        return currentIndex++;
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        return instance[_index].playersConcern[_user];
    }

    function getState(uint256 _index, address _user) public view returns (uint256) {
        return instance[_index].revealIndex;
    }

    function getSubInstances(uint256 _index, address)
        public view returns (address[] memory _addresses,
            uint256[] memory _indices)
    {
        address[] memory a = new address[](1);
        uint256[] memory i = new uint256[](1);
        a[0] = address(rm);
        i[0] = instance[_index].revealIndex;

        return (a, i);
    }


}

