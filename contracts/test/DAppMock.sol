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

/// @title DappMock
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "./RevealMockInterface.sol";
import "@cartesi/util/contracts/Decorated.sol";
import "@cartesi/util/contracts/Instantiator.sol";

contract DAppMock is Decorated, Instantiator{

    RevealMockInterface private rm;

    enum state {
        Idle,
        DAppRunning,
        DAppFinished
    }

    struct DAppMockCtx {
        uint256 revealIndex;
        mapping(address => bool) playersConcern; //player address to isConcerned

        address[] playerAddresses;
        uint256[] scores;
        bytes32[] finalHashes;
        bytes32[] logHashes;
        bytes32[] initialHashes;

        state currentState;
    }

    mapping(uint256 => DAppMockCtx) internal instance;

    constructor(
        address _rmAddress,
        address[] memory _playerAddresses,
        uint256[] memory _scores,
        bytes32[] memory _finalHashes,
        bytes32[] memory _logHashes,
        bytes32[] memory _initialHashes
    ) public {
        require(_playerAddresses.length == _scores.length && _scores.length == _finalHashes.length, "Arrays should have the same length");

        currentIndex = 0;

        rm = RevealMockInterface(_rmAddress);
        // add user to concern
        for (uint256 i = 0; i < _playerAddresses.length; i++) {
            instance[currentIndex].playersConcern[_playerAddresses[i]] = true;
        }

        instance[currentIndex].playerAddresses = _playerAddresses;
        instance[currentIndex].scores = _scores;
        instance[currentIndex].logHashes = _logHashes;
        instance[currentIndex].initialHashes = _initialHashes;
        instance[currentIndex].finalHashes = _finalHashes;
        instance[currentIndex].currentState = state.Idle;

        active[currentIndex] = true;

        currentIndex++;
    }

    function claimDAppRunning(uint256 _index) public {
        require(instance[_index].currentState == state.Idle, "State has to be Idle");
        instance[_index].currentState = state.DAppRunning;

        // this also instantiate match manager
        instance[_index].revealIndex = rm.instantiate(
            200, //commit duration
            200, //reveal duration
            100, //epoch duration
            50, //match duration
            25, //round duration
            13000, // final time
            bytes32("0xc7e2"), //inital hash
            address(0) //machine address
        );

        //// also have to add yourself
        rm.addFakePlayers(instance[_index].revealIndex, instance[_index].playerAddresses, instance[_index].scores, instance[_index].logHashes, instance[_index].initialHashes, instance[_index].finalHashes);
        return;
    }

    function claimFinished(uint256 _index) public
        onlyInstantiated(_index)
    {
        require(instance[_index].currentState == state.DAppRunning, "The state is already Finished");

        bytes32 mockRevealState = rm.getCurrentState(instance[_index].revealIndex, msg.sender);

        if (mockRevealState == "TournamentOver") {
            instance[currentIndex].currentState = state.DAppFinished;
        } else {
            revert("The subinstance compute is still active");
        }
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        return instance[_index].playersConcern[_user];
    }

    function getState(uint256 _index, address _user) public view returns (uint256, bytes32) {
        return (instance[_index].revealIndex, getCurrentState(_index, _user));
    }

    function getCurrentState(uint256 _index, address) public view
        onlyInstantiated(_index)
        returns (bytes32)
    {
        if (instance[_index].currentState == state.Idle) {
            return "Idle";
        }

        if (instance[_index].currentState == state.DAppRunning) {
            return "DAppRunning";
        }
        if (instance[_index].currentState == state.DAppFinished) {
            return "DAppFinished";
        }

        require(false, "Unrecognized state");
    }

    function getSubInstances(uint256 _index, address)
        public view returns (address[] memory _addresses,
            uint256[] memory _indices)
    {
        address[] memory a;
        uint256[] memory i;

        if (instance[_index].currentState == state.DAppRunning) {
            a = new address[](1);
            i = new uint256[](1);
            a[0] = address(rm);
            i[0] = instance[_index].revealIndex;
            return (a, i);
        }
        a = new address[](0);
        i = new uint256[](0);
        return (a, i);
    }
}

