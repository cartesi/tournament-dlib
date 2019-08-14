/// @title MatchMangerInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Decorated.sol";
import "./MatchManagerInterface.sol";
import "./MatchInterface.sol";

contract MatchManagerInstantiator is MatchManagerInterface, Decorated {

    MatchInterface private matchInstantiator;

    struct MatchManagerCtx {
        uint256 matchRoundDuration;
        uint256 currentRound;
        uint256 tournamentStartTime;
        uint256 totalPlayers;
        uint256 playersRemaining;
        address unmatchedPlayer;
        mapping(address => MatchInstantiator.MatchCtx[]) matches;
        mapping(address => Player) players;
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

    mapping(uint256 => MatchManagerCtx) internal instance;

    constructor(address _matchInstantiatorAddress) public {
        matchInstantiator = MatchInstantiator(_matchInstantiatorAddress);
    }

    function instantiate(
        uint256 _matchRoundDuration,
        uint256 _tournamentStartTime,
        uint256 _totalPlayers,
        uint256 _playersRemaining,
        address _machineAddress) public returns (uint256)
    {
        MatchManagerCtx storage currentInstance = instance[currentIndex];
        currentInstance.matchRoundDuration = _matchRoundDuration;
        currentInstance.machineAddress = _machineAddress;
        currentInstance.unmatchedPlayer = address(0);
        currentInstance.currentRound = 0;
        currentInstance.tournamentStartTime = now;
        currentInstance.totalPlayers = 0;
        currentInstance.playersRemaining = 0;

        currentInstance.currentState = state.WaitingSignUps;

    }

    function registerToFirstRound(
        uint256 _index,
        uint256 _finalTime,
        uint256 _score,
        bytes32 _initialHash,
        bytes32 _finalHash
    ) public {
        // Require that score is contained on finalHash
        // Require that player has successfully completed reveal phase
        require(instance[_index].currentRound == 0, "current round has to be zero");
        require(instance[_index].currentState == state.WaitingSignUps, "State has to be Waiting SignUps");
        //cheap way to check if player has been registered
        require(instance[_index].players[msg.sender].playerAddr == address(0), "Player cannot register twice");

        Player player = new Player();
        player.playerAddr = msg.sender;
        player.roundsWon = 0;
        player.score = _score;
        player.finalTime = _finalTime;
        player.initialHash = _initialHash;
        player.finalHash = _finalHash;
        // add player to Match Manager intance
        instance[_index].players[msg.sender] = player;

        address unmatchedAddr = instance[_index].unmatchedPlayer;
        address claimer;
        address challenger;

        if (unmatchedAddr != address(0)) {
            // there is one unmatched player ready for a match

            // the highest score between both is the claimer, the lowest is the challenger
            if (_score > instance[_index].players[unmatchedaddr].score) {
                claimer = msg.sender;
                challenger = instance[_index].players[unmatchedaddr].score;
            } else {
                challenger = msg.sender;
                claimer = instance[_index].players[unmatchedaddr].score;

            }

            // instantiate new match
            newMatch = MatchCtx.instantiate(
                challenger,
                claimer,
                instance[_index].matchRoundDuration,
                instance[_index].machineAddress,
                instance[_index].players[claimer].initialHash,
                instance[_index].players[claimer].finalHash,
                instance[_index].players[claimer].finalTime
            );

            // add match to both players mapping
            instance[_index].matches[challenger] = newMatch;
            instance[_index].matches[claimer] = newMatch;

            totalPlayers += 2;
            playersRemaining += 2;

        } else {
            instance[_index].unmatchedPlayer = msg.sender;
        }
    }

}
