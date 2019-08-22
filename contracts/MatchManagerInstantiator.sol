/// @title MatchMangerInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Decorated.sol";
import "./MatchManagerInterface.sol";
import "./MatchInterface.sol";

contract MatchManagerInstantiator is MatchManagerInterface, Decorated {

    MatchInterface private mi;

    struct MatchManagerCtx {
        uint256 epochDuration;
        uint256 roundDuration;
        uint256 currentEpoch;
        uint256 lastEpochStartTime;
        mapping(uint256 => uint256) numbersOfMatchesOnEpoch;
        address unmatchedPlayer;
        mapping(address => uint256) lastMatchIndex;
        mapping(address => Player) players;
        address machineAddress;

        state currentState;
    }

    struct Player {
        address playerAddr;
        uint256 finalTime;
        uint256 score;
        bytes32 initialHash;
        bytes32 finalHash;
    }

    mapping(uint256 => MatchManagerCtx) internal instance;

    constructor(address _miAddress) public {
        mi = MatchInterface(_miAddress);
    }

    function instantiate(
        uint256 _epochDuration,
        uint256 _roundDuration,
        address _machineAddress) public returns (uint256)
    {
        MatchManagerCtx storage currentInstance = instance[currentIndex];
        currentInstance.epochDuration= _epochDuration;
        currentInstance.roundDuration= _roundDuration;
        currentInstance.machineAddress = _machineAddress;
        currentInstance.unmatchedPlayer = address(0);
        currentInstance.currentEpoch = 0;
        currentInstance.lastEpochStartTime = now;

        currentInstance.currentState = state.WaitingSignUps;

    }

    function playNextEpoch(uint256 _index) public {
        // Advance epoch if deadline has been met
        if (now > (instance[_index].lastEpochStartTime + ((1 + instance[_index].currentEpoch) * instance[_index].epochDuration))) {
            instance[_index].currentEpoch++;
            instance[_index].lastEpochStartTime = now;
        }

            uint256 matchIndex = instance[_index].lastMatchIndex[msg.sender];
        require (msg.sender != instance[_index].unmatchedPlayer, "Player is already registered to this epoch");
        require (
                mi.getEpochNumber(matchIndex) + 1 == instance[_index].currentEpoch,
                "Last match played by player has to be compatible with current currentEpoch"
        );

        // TO-DO: find a decent way to format this
        require (
            (mi.stateIsFinishedChallengerWon(matchIndex) && mi.isChallenger(matchIndex, msg.sender)) ||
            (mi.stateIsFinishedClaimerWon(matchIndex) && mi.isClaimer(matchIndex, msg.sender)),
            "Player must have won last match played"
         );

         if (instance[_index].unmatchedPlayer != address(0)) {
            // there is one unmatched player ready for a match
            createMatch(_index);

            // clears unmatched player
            instance[_index].unmatchedPlayer = address(0);

        } else {
            instance[_index].unmatchedPlayer = msg.sender;
        }

    }

    function registerToFirstEpoch(
        uint256 _index,
        uint256 _finalTime,
        uint256 _score,
        bytes32 _initialHash,
        bytes32 _finalHash
    ) public {
        // Require that score is contained on finalHash
        // Require that player has successfully completed reveal phase
        require(instance[_index].currentEpoch == 0, "current round has to be zero");
        require(instance[_index].currentState == state.WaitingSignUps, "State has to be Waiting SignUps");
        //cheap way to check if player has been registered
        require(instance[_index].players[msg.sender].playerAddr == address(0), "Player cannot register twice");

        Player memory player;
        player.playerAddr = msg.sender;
        player.score = _score;
        player.finalTime = _finalTime;
        player.initialHash = _initialHash;
        player.finalHash = _finalHash;
        // add player to Match Manager intance
        instance[_index].players[msg.sender] = player;

        if (instance[_index].unmatchedPlayer != address(0)) {
            // there is one unmatched player ready for a match
            createMatch(_index);

            // clears unmatched player
            instance[_index].unmatchedPlayer = address(0);

        } else {
            instance[_index].unmatchedPlayer = msg.sender;
        }
    }

    function createMatch(uint256 _index) private {
        address claimer;
        address challenger;
        address unmatchedAddr = instance[_index].unmatchedPlayer;

        // the highest score between both is the claimer, the lowest is the challenger
        if (instance[_index].players[msg.sender].score
 > instance[_index].players[unmatchedAddr].score) {
            claimer = msg.sender;
            challenger = unmatchedAddr;
        } else {
            challenger = msg.sender;
            claimer = unmatchedAddr;

        }

        // instantiate new match
        uint256 newMatchIndex = mi.instantiate(
            challenger,
            claimer,
            now,
            instance[_index].roundDuration,
            instance[_index].machineAddress,
            instance[_index].players[claimer].initialHash,
            instance[_index].players[claimer].finalHash,
            instance[_index].players[claimer].finalTime,
            now
        );

        // add match to both players mapping
        instance[_index].lastMatchIndex[challenger] = newMatchIndex;
        instance[_index].lastMatchIndex[claimer] = newMatchIndex;

        // increase matches on epoch counter
        instance[_index].numbersOfMatchesOnEpoch[instance[_index].currentEpoch]++;

    }

    function claimWin(uint256 _index) public returns (address) {
        bool isEpochOver = (now > (instance[_index].lastEpochStartTime + ((1 + instance[_index].currentEpoch) * instance[_index].epochDuration)));
        if (isEpochOver && (instance[_index].numbersOfMatchesOnEpoch[instance[_index].currentEpoch] == 0)) {
            return instance[_index].unmatchedPlayer;
        }
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        return instance[_index].players[_user].playerAddr != address(0);
    }

    function getState(uint256 _index, address _user) public view returns
        ( uint256 epochDuration,
          uint256 roundDuration,
          uint256 currentEpoch,
          uint256 lastEpochStartTime,
          uint256 numbersOfMatchesOnLastEpoch,
          address unmatchedPlayer,
          uint256 lastMatchIndex,
          address machineAddress,
          state currentState
        ) {

            return (
                instance[_index].epochDuration,
                instance[_index].roundDuration,
                instance[_index].currentEpoch,
                instance[_index].lastEpochStartTime,
                instance[_index].numbersOfMatchesOnEpoch[instance[_index].currentEpoch],
                instance[_index].unmatchedPlayer,
                instance[_index].lastMatchIndex[_user],
                instance[_index].machineAddress,
                instance[_index].currentState

            );
        }
}

