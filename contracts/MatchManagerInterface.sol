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

    function getCurrentState(uint256 _index, address concernedAddress) public view returns (bytes32);

    function instantiate(
        uint256 matchRoundDuration,
        uint256 tournamentStartTime,
        uint256 totalPlayers,
        uint256 playersRemaining,
        address machineAddress) public returns (uint256);

    function registerToFirstRound(
        uint256 _index,
        uint256 _finalTime,
        uint256 _score,
        bytes32 _initialHash,
        bytes32 _finalHash
    ) public;
    function advanceToNextRound(uint256 _index) public;
    function claimWin(uint256 _index) public;

    function isConcerned(uint256 _index, address _user) public view returns (bool);
}

