// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "forge-std/Test.sol";
import {LibStrings} from "contracts/libraries/LibStrings.sol";

/**
 * @dev common utilities for forge tests
 */
contract Utils is Test {
    using LibStrings for uint256;
    using LibStrings for bytes;
    address payable[] internal users;

    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    /// @dev impersonate `from`
    modifier prank(address from) {
        vm.startPrank(from);
        _;
        vm.stopPrank();
    }

    function getNextUserAddress() public returns (address payable) {
        //bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    // create users with 100 ether balance
    function createUsers(uint256 userNum) public returns (address payable[] memory) {
        address payable[] memory _users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = this.getNextUserAddress();
            vm.label(user, string(abi.encodePacked("Farmer ", i.toString())));
            vm.deal(user, 100 ether);
            _users[i] = user;
        }
        return _users;
    }

    function toStalk(uint256 stalk) public pure returns (uint256) {
        return stalk * 1e10;
    }
}
