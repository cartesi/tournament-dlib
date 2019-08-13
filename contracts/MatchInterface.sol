/// @title MatchInterface
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Instantiator.sol";

contract MatchInterface is Instantiator {
    enum state {
        ChallengerMissedDeadline,
        ClaimerMissedDeadline,
        WaitingChallenge,
        ChallengerWon,
        ClaimerWon
    }
    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

    function instantiate(
        address _challenger,
        address _claimer,
        uint256 _roundStart,
        uint256 _roundDuration,
        address _machineAddress,
        bytes32 _initialHash,
        bytes32 _finalHash,
        uint256 _finalTime) public returns (uint256);

    function claimNextRoundSpot(uint256 _index) public;
    function challengeClaim(uint256 _index) public;
    function winByVG(uint256 _index) public;
    function claimVictoryByTime(uint256 _index) public;
    function isConcerned(uint256 _index, address _user) public view returns (bool);

}

