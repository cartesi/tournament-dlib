/// @title MatchMangerInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Decorated.sol";
import "./MatchInstantiator.sol";
import "./MatchManagerInterface.sol";

contract MatchManagerInstantiator is MatchManagerInterface, Decorated {

    struct MatchManagerCtx {
        uint256 matchRoundDuration;
        uint256 currentRound;
        uint256 tournamentStartTime;
        uint256 totalPlayers;
        uint256 playersRemaining;
        address[] unmatchedPlayers;
        mapping(address => MatchInstantiator.MatchCtx[]) matches;
        address machineAddress;

        state currentState;
    }

    struct Player {
        address playerAddr;
        uint256 finalTime;
        uint256 roundsWon;
        uint256 score;
        bytes32 initialHash;
        bytes32 finalHash;
    }
}
