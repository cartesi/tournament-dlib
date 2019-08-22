/// @title MatchInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Instantiator.sol";

contract MatchInterface is Instantiator {

    enum state {
        WaitingChallenge,
        ChallengeStarted,
        ChallengerWon,
        ClaimerWon
    }

    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _epochNumber,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        uint256 _timeOfLastMove) public returns (uint256);

    function challengeHighestScore(uint256 _index) public;

    function defendHighestScore(uint256 _index) public;

    function winByVG(uint256 _index) public;

    function claimVictoryByTime(uint256 _index) public;

    function stateIsFinishedClaimerWon(uint256 _index) public view returns (bool);

    function stateIsFinishedChallengerWon(uint256 _index) public view returns (bool);

    function getEpochNumber(uint256 _index) public view returns (uint256);

    function isClaimer(uint256 _index, address addr) public view returns (bool);

    function isChallenger(uint256 _index, address addr) public view returns (bool);

    function isConcerned(uint256 _index, address _user) public view returns (bool);

    function getState(uint256 _index, address _user) public view returns
    (   address _challenger,
        address _claimer,
        uint256 _epochNumber,
        uint256 _roundDuration,
        uint256 _timeOfLastMove,
        address _machine,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime,
        state _currentState
   );

}

