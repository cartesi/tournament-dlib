/// @title RevealInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Decorated.sol";
import "../../arbitration-dlib/contracts/VGInterface.sol";
import "./RevealInterface.sol";

contract RevealInstantiator is RevealInterface, Decorated {
    struct RevealCtx {
        uint256 revealDuration;
        mapping(address => Player) players;
    }
    struct Player {
        address playerAddr;
        uint256 finalTime;
        uint256 score;
        bytes32 initialHash;
        bytes32 finalHash;
    }
    
    mapping(uint256 => RevealCtx) internal instance;

    function getScore(uint256 _index, address _playerAddr) public returns (uint256) {
        return instance[_index].players[msg.sender].score;
    }

    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        return instance[_index].players[_playerAddr].finalHash;
    }

    function playerExist(uint256 _index, address _playerAddr) public returns (bool) {
        //cheap way to check if player has been registered
        return !(instance[_index].players[_playerAddr].playerAddr == address(0));
    }

    function removePlayer(uint256 _index, address _playerAddr) public {
        instance[_index].players[_playerAddr].playerAddr = address(0);    
    }

}

