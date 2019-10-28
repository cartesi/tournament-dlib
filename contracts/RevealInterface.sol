/// @title RevealInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "./Instantiator.sol";

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
        uint256 _scoreWordPosition,
        uint256 _logDrivePosition,
        uint256 _scoreDriveLogSize,
        uint256 _logDriveLogSize,
        bytes32 _emptyLogDriveHash) public returns (uint256);

    function getScore(uint256 _index, address _playerAddr) public returns (uint256);

    function getInitialHash(uint256 _index, address _playerAddr) public returns (bytes32);

    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32);

    function playerExist(uint256 _index, address _playerAddr) public returns (bool);

    function isConcerned(uint256 _index, address _user) public view returns (bool);

    function getCurrentState(uint256 _index) public view returns (bytes32);

    function getState(uint256 _index, address)
    public view returns (
         uint256 instantiatedAt,
         uint256 commitDuration,
         uint256 revealDuration,
         uint256 finalTime,
         bytes32 pristineHash,
         uint256 scoreDrivePosition,
         uint256 logDrivePosition,
         uint256 scoreDriveLogSize,
         uint256 logDriveLogSize,
         bool hasRevealed,

         bytes32 currentState
    );

}
