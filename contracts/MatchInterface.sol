/// @title MatchInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import ".//Instantiator.sol";

contract MatchInterface is Instantiator {

    enum state {
        WaitingChallenge,
        ChallengeStarted,
        ChallengerWon,
        ClaimerWon
    }

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _epochNumber,
        uint256 _matchDuration,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _logHash,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        uint256 _timeOfLastMove) public returns (uint256);

    function challengeHighestScore(uint256 _index) public;
    function winByVG(uint256 _index) public;
    function claimVictoryByTime(uint256 _index) public;
    function stateIsFinishedClaimerWon(uint256 _index) public view returns (bool);
    function stateIsFinishedChallengerWon(uint256 _index) public view returns (bool);
    function getEpochNumber(uint256 _index) public view returns (uint256);
    function isClaimer(uint256 _index, address addr) public view returns (bool);
    function isChallenger(uint256 _index, address addr) public view returns (bool);
    function isConcerned(uint256 _index, address _user) public view returns (bool);
    function getState(uint256 _index, address) public view returns
    (   address[3] memory _addressValues,
        uint256[4] memory _uintValues,
        bytes32[3] memory _bytesValues,
        bytes32 _currentState
   );

}

