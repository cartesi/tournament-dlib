// Copyright (C) 2020 Cartesi Pte. Ltd.

// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Note: This component currently has dependencies that are licensed under the GNU
// GPL, version 3, and so you should treat this component as a whole as being under
// the GPL version 3. But all Cartesi-written code in this component is licensed
// under the Apache License, version 2, or a compatible permissive license, and can
// be used independently under the Apache v2 license. After this component is
// rewritten, the entire component will be released under the Apache v2 license.

/// @title RevealInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "@cartesi/util/contracts/Decorated.sol";
import "./RevealMockInterface.sol";
import "../MatchManagerInterface.sol";

contract RevealMock is Decorated, RevealMockInterface {

    MatchManagerInterface private mmi;

    struct RevealCtx {
        uint256 commitDuration;
        uint256 revealDuration;
        uint256 matchManagerIndex;
        uint256 matchManagerEpochDuration;
        uint256 matchManagerMatchDuration;
        uint256 matchManagerRoundDuration;
        uint256 finalTime;
        bytes32 initialHash;
        address machineAddress;
        mapping(address => Player) players; //player address to player

        state currentState;
    }

    struct Player {
        address playerAddr;
        bool hasRevealed;
        uint256 score;
        bytes32 initialHash;
        bytes32 finalHash;
        bytes32 logHash;
    }

    event logCommited(uint256 index, address player, bytes32 logHash, uint256 block);
    event logRevealed(uint256 index, address player, bytes32 logHash, uint256 block);

    mapping(uint256 => RevealCtx) internal instance;

    constructor(address _mmiAddress) public {
        mmi = MatchManagerInterface(_mmiAddress);
    }

    function addFakePlayers(uint256 _index, address[] memory _playerAddresses, uint256[] memory _scores, bytes32[] memory _logHashes, bytes32[] memory _initialHashes, bytes32[] memory _finalHashes) public {
        for (uint256 i = 0; i < _playerAddresses.length; i++) {
            Player memory newPlayer;
            newPlayer.playerAddr = _playerAddresses[i];
            newPlayer.score = _scores[i];
            newPlayer.finalHash = _finalHashes[i];
            newPlayer.initialHash = _initialHashes[i];
            newPlayer.logHash = _logHashes[i];
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
        uint256 _matchManagerRoundDuration,
        uint256 _finalTime,
        bytes32 _initialHash,
        address _machineAddress) public returns (uint256)
    {
        RevealCtx storage currentInstance = instance[currentIndex];
        currentInstance.commitDuration = _commitDuration;
        currentInstance.revealDuration = _revealDuration;
        currentInstance.matchManagerEpochDuration = _matchManagerEpochDuration;
        currentInstance.matchManagerMatchDuration = _matchManagerMatchDuration;
        currentInstance.matchManagerRoundDuration = _matchManagerRoundDuration;
        currentInstance.finalTime = _finalTime;
        currentInstance.initialHash = _initialHash;
        currentInstance.machineAddress = _machineAddress;

        currentInstance.currentState = state.MatchManagerPhase;

        // instantiate MatchManager
        instance[currentIndex].matchManagerIndex = mmi.instantiate(
            instance[currentIndex].matchManagerRoundDuration,
            instance[currentIndex].finalTime,
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
    function reveal(uint256 _index, uint256, bytes32) public view {
        require(instance[_index].currentState == state.RevealPhase, "State has to be reveal phase");
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

    function getLogHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        require(playerExist(_index, _playerAddr), "Player has to exist");
        return instance[_index].players[_playerAddr].logHash;
    }

    function getInitialHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        require(playerExist(_index, _playerAddr), "Player has to exist");
        return instance[_index].players[_playerAddr].initialHash;
    }


    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        return instance[_index].players[_playerAddr].finalHash;
    }

    function playerExist(uint256, address) public returns (bool) {
        //cheap way to check if player has been registered
        return true; //!(instance[_index].players[_playerAddr].playerAddr == address(0));
    }

    function removePlayer(uint256 _index, address _playerAddr) public {
        instance[_index].players[_playerAddr].playerAddr = address(0);
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {

        return instance[_index].players[_user].playerAddr != address(0)? true : false;
    }

    function getCurrentState(uint256 _index, address) public view returns (bytes32) {
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
        (
            uint[5] memory _uintValues,
            bytes32 _initialHash,
            address _machineAddress,
            bytes32 currentState
        ) {

        RevealCtx memory i = instance[_index];

        uint[5] memory uintValues = [
            i.commitDuration,
            i.revealDuration,
            i.matchManagerEpochDuration,
            i.matchManagerMatchDuration,
            i.finalTime
        ];

        return (
            uintValues,
            i.initialHash,
            i.machineAddress,
            getCurrentState(_index, _user)
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
