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

pragma solidity ^0.5.0;

import "@cartesi/util/contracts/Decorated.sol";
import "@cartesi/logger/contracts/LoggerInterface.sol";
import "@cartesi/util/contracts/Merkle.sol";

//////////////////////////////////////////////////////////////
//
// THIS IS A MOCK CONTRACT, SHOULD NEVER BE USED IN PRODUCTION
//
//////////////////////////////////////////////////////////////


/// @title Logger Mock
/// @notice A contract that offers data availability
/// @dev This contract is not well-tested yet.
contract LoggerMock is Decorated, LoggerInterface {
  // the caller can either provide the full data to generate the Merkle tree root
  // or combine the existing hashes in the history to a deeper tree

    struct DataEntry {
        // TODO: change the type of log2Size based on the max log size(disk size) of the DApp
        uint64 log2Size;
        bytes32 root;
    }

    mapping(bytes32 => bool) logSubmitted;
    DataEntry[] dataHistory;

    uint256 public currentIndex = 0;

    // TODO: get rid of the _data from event
    event MerkleRootCalculatedFromData(uint256 indexed _index, bytes8[] _data, bytes32 indexed _root, uint64 _log2Size);
    event MerkleRootCalculatedFromHistory(uint256 indexed _index, uint256[] _indices, bytes32 indexed _root, uint64 _log2Size);

    // TODO: This function should never exist in the production version
    function mockAddHashWithoutVerification(bytes32 _hash) public {
        logSubmitted[_hash] = true;
    }

    /// @notice Calculate the Merkle tree and return the root hash
    // @param _hashes The array of words of the file
    function calculateMerkleRootFromData(uint64 _log2Size, bytes8[] memory _data) public returns(bytes32) {
        require(_data.length > 0, "The input array cannot be empty");

        // uint64 log2Size = Merkle.getLog2Floor(_data.length);
        bytes8[] memory data = _data;
        uint256 power2Length = uint256(2) ** (_log2Size);

        // if (!Merkle.isPowerOf2(_data.length)) {
        if (_data.length != power2Length) {
            // pad the list to length of power of 2
            bytes8[] memory paddedData = new bytes8[](power2Length);

            for (uint256 i = 0; i < _data.length; ++i) {
                paddedData[i] = _data[i];
            }
            for (uint256 i = _data.length; i < paddedData.length; ++i) {
                paddedData[i] = 0;
            }
            data = paddedData;
        }

        bytes32[] memory hashes = new bytes32[](data.length);

        for (uint256 i = 0; i<data.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(data[i]));
        }

        bytes32 root = Merkle.calculateRootFromPowerOfTwo(hashes);
        dataHistory.push(DataEntry(_log2Size, root));
        emit MerkleRootCalculatedFromData(
            currentIndex,
            _data,
            root,
            _log2Size);
        ++currentIndex;
        logSubmitted[root] = true;
        return root;
    }

    /// @notice Calculate the Merkle tree and return the root hash
    // @param _indices The array of indices of the history
    function calculateMerkleRootFromHistory(uint64 _log2Size, uint256[] memory _indices) public returns(bytes32) {
        require(Merkle.isPowerOf2(_indices.length), "The input array must contain power of 2 elements");

        // check indices exist and the value of log2Size matches
        for (uint256 i = 0; i<_indices.length; ++i) {
            require(currentIndex > _indices[i], "The index of history doesn't exist yet");
            require(_log2Size == dataHistory[_indices[i]].log2Size, "The value of log2Size doesn't match in history");
        }

        bytes32[] memory hashes = new bytes32[](_indices.length);
        for (uint256 i = 0; i<_indices.length; ++i) {
            hashes[i] = dataHistory[_indices[i]].root;
        }

        bytes32 root = Merkle.calculateRootFromPowerOfTwo(hashes);

        uint64 log2Size = Merkle.getLog2Floor(_indices.length);
        dataHistory.push(DataEntry(log2Size + _log2Size, root));
        emit MerkleRootCalculatedFromHistory(
            currentIndex,
            _indices,
            root,
            log2Size + _log2Size);
        ++currentIndex;
        logSubmitted[root] = true;
        return root;
    }

    /// @notice Getter function to check if log has been submitted for the given hash
    // @param _indices The array of indices of the history
    function isLogAvailable(bytes32 _root) public view returns(bool) {
        return logSubmitted[_root];
    }
}
