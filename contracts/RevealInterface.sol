/// @title RevealInterface
/// @author Felipe Argento
pragma solidity ^0.5.0;

import "../../arbitration-dlib/contracts/Instantiator.sol";

contract RevealInterface is Instantiator {
    function getScore(uint256 _index, address _playerAddr) public returns (uint256);

    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32);

    function playerExist(uint256 _index, address _playerAddr) public returns (bool);

    function removePlayer(uint256 _index, address _playerAddr) public ;

}
