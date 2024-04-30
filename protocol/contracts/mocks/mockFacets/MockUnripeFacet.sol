/*
 SPDX-License-Identifier: MIT
*/

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import "contracts/beanstalk/barn/UnripeFacet.sol";
import "contracts/libraries/LibAppStorage.sol";
import "contracts/libraries/LibTractor.sol";

/**
 * @author Publius
 * @title Mock Unripe Facet
 **/
contract MockUnripeFacet is UnripeFacet {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    function setMerkleRootE(address unripeToken, bytes32 root) external {
        s.u[unripeToken].merkleRoot = root;
    }

    function addUnderlying(address unripeToken, uint256 amount)
        external
        payable
        nonReentrant
    {
        address underlyingToken = s.u[unripeToken].underlyingToken;
        IERC20(underlyingToken).safeTransferFrom(LibTractor._user(), address(this), amount);
        s.u[unripeToken].balanceOfUnderlying = s.u[unripeToken].balanceOfUnderlying.add(amount);
    }

    function addUnderlyingWithRecap(
        address unripeToken,
        uint256 amount
    ) external payable nonReentrant {
        address underlyingToken = s.u[unripeToken].underlyingToken;
        IERC20(underlyingToken).safeTransferFrom(LibTractor._user(), address(this), amount);
        LibUnripe.addUnderlying(unripeToken, amount);
    }

    function resetUnderlying(address unripeToken) external {
        s.u[unripeToken].balanceOfUnderlying = 0;
    }
}
