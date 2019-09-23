/// @title Dapp
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "./RevealMock.sol";

contract DApp {
    uint256 index;

    constructor (
        address[] memory _playerAddresses,
        uint256[] memory _scores,
        bytes32[] memory _finalHashes
    ) public
    {
        // this also instantiate match manager
        RevealMock rm = new RevealMock();
        index = rm.instantiate(
            0, //commit duration
            0, //reveal duration
            5000, //epoch duration
            200, //match duration
            0, // final time
            "0x00", //inital hash
            address(0) //machine address
        );

        // also have to add yourself
        rm.addFakePlayers(index, _playerAddresses, _scores, _finalHashes);
    }


}

