/// @title MatchMangerInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Decorated.sol";
import "./MatchManagerInterface.sol";
import "./RevealInterface.sol";
import "./MatchInterface.sol";

// TO-DO: how should the parent(reveal) be called?
contract MatchManagerInstantiator is MatchManagerInterface, Decorated {

    MatchInterface private mi;

    struct MatchManagerCtx {
        uint256 epochDuration;
        uint256 roundDuration;
        uint256 currentEpoch;
        uint256 finalTime;
        uint256 lastEpochStartTime;
        mapping(uint256 => uint256) numberOfMatchesOnEpoch; // epoch index to number of matches
        address unmatchedPlayer;
        mapping(address => uint256) lastMatchIndex; // player address to index of his last played match
        mapping(address => bool) registered; // player address to true if he is registered
        bytes32 initialHash;
        address machineAddress;
        address revealAddress;
        uint256 revealInstance;

        state currentState;
    }

    mapping(uint256 => MatchManagerCtx) internal instance;

    constructor(address _miAddress) public {
        mi = MatchInterface(_miAddress);
    }

    function instantiate(
        uint256 _epochDuration,
        uint256 _roundDuration,
        uint256 _finalTime,
        bytes32 _initialHash,
        address _revealAddress,
        uint256 _revealInstance,
        address _machineAddress) public returns (uint256)
    {
        MatchManagerCtx storage currentInstance = instance[currentIndex];
        currentInstance.epochDuration = _epochDuration;
        currentInstance.roundDuration = _roundDuration;
        currentInstance.finalTime = _finalTime;
        currentInstance.initialHash = _initialHash;
        currentInstance.machineAddress = _machineAddress;
        currentInstance.revealAddress = _revealAddress;
        currentInstance.revealInstance = _revealInstance;
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

    function registerToFirstEpoch(uint256 _index) public {
        require(instance[_index].currentEpoch == 0, "current round has to be zero");
        require(instance[_index].currentState == state.WaitingSignUps, "State has to be Waiting SignUps");

        RevealInterface reveal = RevealInterface(instance[_index].revealAddress);
        //cheap way to check if player has been registered
        require(reveal.playerExist(instance[_index].revealInstance, msg.sender), "Player must have completed reveal phase");
        require(!instance[_index].registered[msg.sender], "Player cannot register twice");

        instance[_index].registered[msg.sender] = true;

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

        RevealInterface reveal = RevealInterface(instance[_index].revealAddress);

        // the highest score between both is the claimer, the lowest is the challenger
        if (reveal.getScore(instance[_index].revealInstance, msg.sender) > reveal.getScore(instance[_index].revealInstance, unmatchedAddr)) {
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
            reveal.getFinalHash(instance[_index].revealInstance, claimer),
            instance[_index].finalTime,
            now
        );

        // add match to both players mapping
        instance[_index].lastMatchIndex[challenger] = newMatchIndex;
        instance[_index].lastMatchIndex[claimer] = newMatchIndex;

        // increase matches on epoch counter
        instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch]++;

    }

    function claimWin(uint256 _index) public returns (address) {
        require(instance[_index].currentState != state.MatchesOver, "PLayer cannot claim win multiple times");
        bool isEpochOver = (now > (instance[_index].lastEpochStartTime + ((1 + instance[_index].currentEpoch) * instance[_index].epochDuration)));
        if (isEpochOver && (instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch] == 0)) {
            instance[_index].currentState = state.MatchesOver;
            return instance[_index].unmatchedPlayer;
        }
    }

    // TO-DO: Remove player from this if he lost it. PlayNextEpoch should remove the loser.
    // doing this will make this func stopping being view
    // TO-DO: this function will probably not exist
    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        // RevealInterface reveal = RevealInterface(instance[_index].revealAddress);

        //bool concerned = reveal.playerExist(instance[_index].revealInstance, _user);

        //return concerned;
        return true;
    }

    function getState(uint256 _index, address _user) public view returns
        ( uint256 epochDuration,
          uint256 roundDuration,
          uint256 currentEpoch,
          uint256 finalTime,
          uint256 lastEpochStartTime,
          uint256 numberOfMatchesOnLastEpoch,
          address unmatchedPlayer,
          uint256 lastMatchIndex,
          bytes32 initialHash,
          address machineAddress,
          address revealAddress,
          uint256 revealInstance,
          uint256 lastMatchEpoch,
          state currentState
        ) {

            return (
                instance[_index].epochDuration,
                instance[_index].roundDuration,
                instance[_index].currentEpoch,
                instance[_index].finalTime,
                instance[_index].lastEpochStartTime,
                instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch - 1],
                instance[_index].unmatchedPlayer,
                instance[_index].lastMatchIndex[_user],
                instance[_index].initialHash,
                instance[_index].machineAddress,
                instance[_index].revealAddress,
                instance[_index].revealInstance,
                mi.getEpochNumber(instance[_index].lastMatchIndex[_user]),
                instance[_index].currentState

            );
        }

        function getSubInstances(uint256 _index, address _user)
            public view returns (address[] memory _addresses,
                uint256[] memory _indices)
        {
            address[] memory a = new address[](1);
            uint256[] memory i = new uint256[](1);
            a[0] = address(mi);
            i[0] = instance[_index].lastMatchIndex[_user];

            return (a, i);
        }

}

