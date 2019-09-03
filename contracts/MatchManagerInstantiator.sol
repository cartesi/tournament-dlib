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
        uint256 finalTime;
        uint256 lastEpochStartTime;
        mapping(uint256 => uint256) numbersOfMatchesOnEpoch;
        address unmatchedPlayer;
        mapping(address => uint256) lastMatchIndex;
        mapping(address => Player) players;
        address machineAddress;
        bytes32 initialHash;

        state currentState;
    }
    // M - struct player vai pro reveal
    // M - get subInstance - só checar lastMatchIndex
    struct Player {
        address playerAddr;
        uint256 finalTime;
        uint256 score;
        bytes32 finalHash;
    }

    mapping(uint256 => MatchManagerCtx) internal instance;

    constructor(address _miAddress) public {
        mi = MatchInterface(_miAddress);
    }

    // M - adicionar endereço e instancia contrato de reveal
    function instantiate(
        uint256 _epochDuration,
        uint256 _roundDuration,
        uint256 _finalTime,
        bytes32 _initialHash,
        address _machineAddress) public returns (uint256)
    {
        MatchManagerCtx storage currentInstance = instance[currentIndex];
        currentInstance.epochDuration= _epochDuration;
        currentInstance.roundDuration= _roundDuration;
        currentInstance.finalTime= _finalTime;
        currentInstance.machineAddress = _machineAddress;
        currentInstance.initialHash= _initialHash;
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
        // require player to have won last match
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
    // M - argumentos seriam só instancia do torneio e do reveal.
    // o resto todo vem do reveal
    function registerToFirstEpoch(
        uint256 _index,
        uint256 _score,
        bytes32 _finalHash
    ) public {
        // Require that score is contained on finalHash // M - this has to go on commit / reveal
        // Require that player has successfully completed reveal phase
        // M - construir linkado com o contrato reveal, fazer um mapping de jogadores aprovados ... tem que ter instancia
        require(instance[_index].currentEpoch == 0, "current round has to be zero");
        require(instance[_index].currentState == state.WaitingSignUps, "State has to be Waiting SignUps");
        //cheap way to check if player has been registered
        require(instance[_index].players[msg.sender].playerAddr == address(0), "Player cannot register twice");

        Player memory player;
        player.playerAddr = msg.sender;
        player.score = _score;
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
            instance[_index].initialHash,
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

    // TO-DO: Remove player from this if he lost it. PlayNextEpoch should remove the loser.
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

