/// @title RevealInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import ".//Decorated.sol";
import "./RevealInterface.sol";
import "./MatchManagerInterface.sol";

contract RevealMock is Decorated, RevealInterface {

    MatchManagerInterface private mmi;

    struct RevealCtx {
        uint256 commitDuration;
        uint256 revealDuration;
        uint256 creationTime;
        uint256 matchManagerIndex;
        uint256 matchManagerEpochDuration;
        uint256 matchManagerMatchDuration;
        uint256 finalTime;
        bytes32 initialHash;
        address machineAddress;
        mapping(address => Player) players; //player address to player

        state currentState;
    }

    struct Player {
        address playerAddr;
        bool hasRevealed;
        bytes32 commit; //list of hashes commited by player
        uint256 score;
        bytes32 finalHash;
    }

    event logCommited(uint256 index, address player, bytes32 logHash, uint256 block);
    event logRevealed(uint256 index, address player, bytes32 logHash, uint256 block);

    mapping(uint256 => RevealCtx) internal instance;

    constructor(address _mmiAddress) public {
        mmi = MatchManagerInterface(_mmiAddress);
    }

    function addFakePlayers(uint256 _index, address[] memory _playerAddresses, uint256[] memory _scores, bytes32[] memory _finalHashes) public {
        for (uint256 i = 0; i < _playerAddresses.length; i++) {
            Player memory newPlayer;
            newPlayer.playerAddr = _playerAddresses[i];
            newPlayer.score = _scores[i];
            newPlayer.finalHash = _finalHashes[i];
            newPlayer.hasRevealed = true;

            instance[_index].players[_playerAddresses[i]] = newPlayer;
        }

    }
    /// @notice Instantiate a commit and reveal instance.
    /// @param _commitDuration commit phase duration in seconds.
    /// @param _revealDuration reveal phase duration in seconds.
    /// @param _matchManagerEpochDuration match manager epoch duration in seconds.
    /// @param _matchManagerMatchDuration match manager match duration in seconds.
    /// @param _finalTime final time of matches being played.
    /// @param _initialHash initial hash of matches being played
    /// @param _machineAddress Machine that will run the challenge.
    /// @return Reveal index.
    function instantiate(
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _matchManagerEpochDuration,
        uint256 _matchManagerMatchDuration,
        uint256 _finalTime,
        bytes32 _initialHash,
        address _machineAddress) public returns (uint256)
    {
        RevealCtx storage currentInstance = instance[currentIndex];
        currentInstance.commitDuration = _commitDuration;
        currentInstance.revealDuration = _revealDuration;
        currentInstance.creationTime = now;
        currentInstance.matchManagerEpochDuration = _matchManagerEpochDuration;
        currentInstance.matchManagerMatchDuration = _matchManagerMatchDuration;
        currentInstance.finalTime = _finalTime;
        currentInstance.initialHash = _initialHash;
        currentInstance.machineAddress = _machineAddress;

        currentInstance.currentState = state.MatchManagerPhase;

        // instantiate MatchManager
        instance[currentIndex].matchManagerIndex = mmi.instantiate(
            instance[currentIndex].matchManagerEpochDuration,
            instance[currentIndex].matchManagerMatchDuration,
            instance[currentIndex].finalTime,
            instance[currentIndex].initialHash,
            address(this),
            currentIndex,
            instance[currentIndex].machineAddress);

        active[currentIndex] = true;
        return currentIndex++;
    }

    /// @notice Submits a commit.
    /// @param _index index of reveal that is being interacted with.
    /// @param _logHash hash of log to be revealed later.

    function commit(uint256 _index, bytes32 _logHash) public {
        require(instance[_index].currentState == state.CommitPhase, "State has to be commit phase");
        emit logCommited(_index, msg.sender, _logHash, block.number);
    }

    /// @notice reveals the log and extracts its information.
    /// @param _index index of reveal that is being interacted with.
    /// @param _score that should be contained in the log
    /// @param _finalHash final hash of the machine after that log has been proccessed.
    function reveal(uint256 _index, uint256 _score, bytes32 _finalHash) public {
        require(instance[_index].currentState == state.RevealPhase, "State has to be reveal phase");
        emit logRevealed(_index, msg.sender, instance[_index].players[msg.sender].commit, block.number);
    }

    function registerToFirstEpoch(uint256 _index) public {
        mmi.registerToFirstEpoch(instance[_index].matchManagerIndex);
    }

    function claimFinished(uint256 _index) public
        onlyInstantiated(_index)
    {
        require(mmi.getCurrentState(instance[_index].matchManagerIndex) == "MatchesOver", "All matches have to be over");

        instance[_index].currentState = state.TournamentOver;
    }

    function getScore(uint256 _index, address _playerAddr) public returns (uint256) {
        return instance[_index].players[_playerAddr].score;
    }

    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        return instance[_index].players[_playerAddr].finalHash;
    }

    function playerExist(uint256 _index, address _playerAddr) public returns (bool) {
        //cheap way to check if player has been registered
        return !(instance[_index].players[_playerAddr].playerAddr == address(0));
    }

    function removePlayer(uint256 _index, address _playerAddr) public {
        instance[_index].players[_playerAddr].playerAddr = address(0);
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {

        return instance[_index].players[_user].playerAddr != address(0)? true : false;
    }

    function getCurrentState(uint256 _index, address _user) public view returns (bytes32) {
        if (instance[_index].currentState == state.CommitPhase) {
            return "CommitPhase";
        }
        if (instance[_index].currentState == state.RevealPhase) {
            return "RevealPhase";
        }
        if (instance[_index].currentState == state.MatchManagerPhase) {
            return "MatchManagerPhase";
        }
        if (instance[_index].currentState == state.TournamentOver) {
            return "TournamentOver";
        }

        require(false, "Unrecognized state");
    }

    function getState(uint256 _index, address _user) public view returns
        (   uint256 _commitDuration,
            uint256 _revealDuration,
            uint256 _matchManagerEpochDuration,
            uint256 _matchManagerMatchDuration,
            uint256 _finalTime,
            bytes32 _initialHash,
            address _machineAddress,
            state currentState
        ) {

            RevealCtx memory i = instance[_index];
         return (
             i.commitDuration,
             i.revealDuration,
             i.matchManagerEpochDuration,
             i.matchManagerMatchDuration,
             i.finalTime,
             i.initialHash,
             i.machineAddress,

             i.currentState
        );
    }

    function getSubInstances(uint256 _index, address)
        public view returns (address[] memory _addresses,
            uint256[] memory _indices)
    {
        address[] memory a = new address[](1);
        uint256[] memory i = new uint256[](1);
        a[0] = address(mmi);
        i[0] = instance[_index].matchManagerIndex;

        return (a, i);
    }

    function clearInstance(uint256 _index) internal {}

}
