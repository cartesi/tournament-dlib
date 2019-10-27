/// @title RevealInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import ".//Instantiator.sol";

contract RevealInterface is Instantiator {

    enum state {
        CommitPhase,
        RevealPhase,
        CommitRevealDone
    }

    function instantiate(
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _finalTime,
        bytes32 _pristineHash,
        uint64 _scoreDrivePosition,
        uint64 _logDrivePosition,
        uint64 _scoreDriveLogSize,
        uint64 _logDriveLogSize) public returns (uint256);

    function getScore(uint256 _index, address _playerAddr) public returns (uint256);
    function getInitalHash(uint256 _index, address _playerAddr) public returns (bytes32);
    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32);
    function playerExist(uint256 _index, address _playerAddr) public returns (bool);
    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

}
