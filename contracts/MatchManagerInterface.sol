/// @title MatchManagerInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Instantiator.sol";

contract MatchManagerInterface is Instantiator {

    enum state {
        WaitingSignUps,
        WaitingMatches,
        MatchesOver
    }

    function instantiate(
        uint256 _epochDuration,
        uint256 _roundDuration,
        uint256 _finalTime,
        uint256 _initialHash,
        address _revealAddress,
        uint256 _revealInstance,
        address _machineAddress) public returns (uint256);

    function registerToFirstEpoch(uint256 _index) public;

    function playNextEpoch(uint256 _index) public;

    function claimWin(uint256 _index) public returns (address);

    function isConcerned(uint256 _index, address _user) public view returns (bool);
    
    function getState(uint256 _index) public view returns
        ( uint256 epochDuration,
          uint256 roundDuration,
          uint256 currentEpoch,
          uint256 lastEpochStartTime,
          uint256 numbersOfMatchesOnLastEpoch,
          address unmatchedPlayer,
          uint256 lastMatchIndex,
          address machineAddress,
          address revealAddress,
          state currentState
        );

    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

}

