/// @title MatchManagerInstantiator
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
        uint256 matchRoundDuration,
        uint256 tournamentStartTime,
        uint256 totalPlayers,
        uint256 playersRemaining,
        address machineAddress) public returns (uint256);

    function registerToFirstEpoch(
        uint256 _index,
        uint256 _finalTime,
        uint256 _score,
        bytes32 _initialHash,
        bytes32 _finalHash
    ) public;

    function registerToFirstRound(uint256 _index) public;

    function advanceToNextRound(uint256 _index) public;

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
          state currentState
        );

    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

}

