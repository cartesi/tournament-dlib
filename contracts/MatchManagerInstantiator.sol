/// @title MatchMangerInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import ".//Decorated.sol";
import "./MatchManagerInterface.sol";
import "./RevealInterface.sol";
import "./MatchInterface.sol";

// TO-DO: how should the parent(reveal) be called?
contract MatchManagerInstantiator is MatchManagerInterface, Decorated {

    MatchInterface private mi;

    // TO-DO: Add match duration + round duration to Instantiator/Match
    // TO-DO: Split registering state into two: can only register if there is epoch duration - match duration time left
    // TO-DO: Propagate changes to offchain code
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

    /// @notice Instantiate a match manager.
    /// @param _epochDuration epoch duration in seconds.
    /// @param _roundDuration duration of a round in seconds.
    /// @param _finalTime final time of matches being played.
    /// @param _initialHash initial hash of matches being played
    /// @param _revealAddress address of parent reveal contract
    /// @param _revealInstance reveal instance that this contract is interacting with
    /// @param _machineAddress Machine that will run the challenge.
    /// @return Match Manager index.

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

        return currentIndex++;
    }

    /// @notice Register for the next Epoch, only doable if you wont a match on last one
    /// @param _index index of matchmanager that youre interacting with

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

    /// @notice Register for the first Epoch
    /// @param _index index of matchmanager that youre interacting with

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

    /// @notice Creates a match with two players
    /// @param _index index of matchmanager that youre interacting with

    function createMatch(uint256 _index) private {

        MatchManagerCtx memory i = instance[_index];

        address claimer;
        address challenger;
        address unmatchedAddr = i.unmatchedPlayer;

        RevealInterface reveal = RevealInterface(instance[_index].revealAddress);

        // the highest score between both is the claimer, the lowest is the challenger
        if (reveal.getScore(i.revealInstance, msg.sender) > reveal.getScore(i.revealInstance, unmatchedAddr)) {
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
            i.roundDuration,
            i.machineAddress,
            i.initialHash,
            reveal.getFinalHash(i.revealInstance, claimer),
            i.finalTime,
            now
        );

        // add match to both players mapping
        instance[_index].lastMatchIndex[challenger] = newMatchIndex;
        instance[_index].lastMatchIndex[claimer] = newMatchIndex;

        // increase matches on epoch counter
        instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch]++;

    }

    /// @notice Claims win on the entire tournament. Only callable if you were unchallenged for an entire epoch
    /// @param _index index of matchmanager that youre interacting with

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
        ( uint256[9] memory _uintValues,
          address[3] memory _addressValues,
          bytes32 initialHash,
          bytes32 currentState
        ) {

            MatchManagerCtx memory i = instance[_index];
            uint256[9] memory uintValues = [
                i.epochDuration,
                i.roundDuration,
                i.currentEpoch,
                i.finalTime,
                i.lastEpochStartTime,
                instance[_index].numberOfMatchesOnEpoch[instance[_index].currentEpoch - 1],
                instance[_index].lastMatchIndex[_user],
                i.revealInstance,
                mi.getEpochNumber(instance[_index].lastMatchIndex[_user])

            ];

            address[3] memory addressValues = [
                i.unmatchedPlayer,
                i.machineAddress,
                i.revealAddress
            ];

            return (
                uintValues,
                addressValues,
                i.initialHash,
                getCurrentState(_index)
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

        function getCurrentState(uint256 _index) public view
            onlyInstantiated(_index)
            returns (bytes32)
        {
            if (instance[_index].currentState == state.WaitingSignUps) {
                return "WaitingSignUps";
            }
            if (instance[_index].currentState == state.WaitingMatches) {
                return "WaitingMatches";
            }
            if (instance[_index].currentState == state.MatchesOver) {
                return "MatchesOver";
            }

            require(false, "Unrecognized state");
        }
}

