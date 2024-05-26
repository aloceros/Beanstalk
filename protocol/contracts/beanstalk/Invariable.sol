// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibRedundantMath256} from "contracts/libraries/LibRedundantMath256.sol";
import {LibRedundantMathSigned256} from "contracts/libraries/LibRedundantMathSigned256.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {C} from "contracts/C.sol";
import {AppStorage} from "contracts/beanstalk/storage/AppStorage.sol";
import {GerminationSide} from "contracts/beanstalk/storage/System.sol";
import {LibAppStorage} from "contracts/libraries/LibAppStorage.sol";
import {LibWhitelistedTokens} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";
import {LibUnripe} from "contracts/libraries/LibUnripe.sol";
import {LibSilo} from "contracts/libraries/Silo/LibSilo.sol";

/**
 * @author funderbrker
 * @title Invariable
 * @notice Implements modifiers that maintain protocol wide invariants.
 * @dev Every external writing function should use as many non-redundant invariant modifiers as possible.
 * @dev https://www.nascent.xyz/idea/youre-writing-require-statements-wrong
 **/
abstract contract Invariable {
    using LibRedundantMath256 for uint256;
    using LibRedundantMathSigned256 for int256;
    using SafeCast for uint256;

    /**
     * @notice Ensures all user asset entitlements are coverable by contract balances.
     * @dev Should be used on every function that can write. Excepting Diamond functions.
     */
    modifier fundsSafu() {
        _;
        address[] memory tokens = getTokensOfInterest();
        (
            uint256[] memory entitlements,
            uint256[] memory balances
        ) = getTokenEntitlementsAndBalances(tokens);
        for (uint256 i; i < tokens.length; i++) {
            require(balances[i] >= entitlements[i], "INV: Insufficient token balance");
        }
    }

    /**
     * @notice Watched token balances do not change and Stalk does not decrease.
     * @dev Applicable to the majority of functions, excepting functions that explicitly move assets.
     * @dev Roughly akin to a view only check where only routine modifications are allowed (ie mowing).
     */
    modifier noNetFlow() {
        uint256 initialStalk = LibAppStorage.diamondStorage().system.silo.stalk;
        address[] memory tokens = getTokensOfInterest();
        uint256[] memory initialProtocolTokenBalances = getTokenBalances(tokens);
        _;
        uint256[] memory finalProtocolTokenBalances = getTokenBalances(tokens);

        require(
            LibAppStorage.diamondStorage().system.silo.stalk >= initialStalk,
            "INV: noNetFlow Stalk decreased"
        );
        for (uint256 i; i < tokens.length; i++) {
            require(
                initialProtocolTokenBalances[i] == finalProtocolTokenBalances[i],
                "INV: noNetFlow Token balance changed"
            );
        }
    }

    /**
     * @notice Watched token balances do not decrease and Stalk does not decrease.
     * @dev Favor noNetFlow where applicable.
     */
    modifier noOutFlow() {
        uint256 initialStalk = LibAppStorage.diamondStorage().system.silo.stalk;
        address[] memory tokens = getTokensOfInterest();
        uint256[] memory initialProtocolTokenBalances = getTokenBalances(tokens);
        _;
        uint256[] memory finalProtocolTokenBalances = getTokenBalances(tokens);

        require(
            LibAppStorage.diamondStorage().system.silo.stalk >= initialStalk,
            "INV: noOutFlow Stalk decreased"
        );
        for (uint256 i; i < tokens.length; i++) {
            require(
                initialProtocolTokenBalances[i] <= finalProtocolTokenBalances[i],
                "INV: noOutFlow Token balance decreased"
            );
        }
    }

    /**
     * @notice All except one watched token balances do not decrease.
     * @dev Favor noNetFlow or noOutFlow where applicable.
     */
    modifier oneOutFlow(address outboundToken) {
        address[] memory tokens = getTokensOfInterest();
        uint256[] memory initialProtocolTokenBalances = getTokenBalances(tokens);
        _;
        uint256[] memory finalProtocolTokenBalances = getTokenBalances(tokens);

        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == outboundToken) {
                continue;
            }
            require(
                initialProtocolTokenBalances[i] <= finalProtocolTokenBalances[i],
                "INV: oneOutFlow multiple token balances decreased"
            );
        }
    }

    /**
     * @notice Does not change the supply of Beans. No minting, no burning.
     * @dev Applies to all but a very few functions tht explicitly change supply.
     */
    modifier noSupplyChange() {
        uint256 initialSupply = C.bean().totalSupply();
        _;
        require(C.bean().totalSupply() == initialSupply, "INV: Supply changed");
    }

    /**
     * @notice Supply of Beans does not increase. No minting.
     * @dev Prefer noSupplyChange where applicable.
     */
    modifier noSupplyIncrease() {
        uint256 initialSupply = C.bean().totalSupply();
        _;
        require(C.bean().totalSupply() <= initialSupply, "INV: Supply increased");
    }

    /**
     * @notice Which tokens to monitor in the invariants.
     */
    function getTokensOfInterest() internal view returns (address[] memory tokens) {
        address[] memory whitelistedTokens = LibWhitelistedTokens.getWhitelistedTokens();
        address sopToken = address(LibSilo.getSopToken());
        if (sopToken == address(0)) {
            tokens = new address[](whitelistedTokens.length);
        } else {
            tokens = new address[](whitelistedTokens.length + 1);
            tokens[tokens.length - 1] = sopToken;
        }
        for (uint256 i; i < whitelistedTokens.length; i++) {
            tokens[i] = whitelistedTokens[i];
        }
    }

    /**
     * @notice Get the Beanstalk balance of an ERC20 token.
     */
    function getTokenBalances(
        address[] memory tokens
    ) internal view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        return balances;
    }

    /**
     * @notice Get protocol level entitlements and balances for all tokens.
     */
    function getTokenEntitlementsAndBalances(
        address[] memory tokens
    ) internal view returns (uint256[] memory entitlements, uint256[] memory balances) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        entitlements = new uint256[](tokens.length);
        balances = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            entitlements[i] =
                s.system.silo.balances[tokens[i]].deposited +
                s.system.silo.germinating[GerminationSide.ODD][tokens[i]].amount +
                s.system.silo.germinating[GerminationSide.EVEN][tokens[i]].amount +
                s.system.internalTokenBalanceTotal[IERC20(tokens[i])];
            if (tokens[i] == C.BEAN) {
                entitlements[i] +=
                    (s.system.fert.fertilizedIndex - s.system.fert.fertilizedPaidIndex) + // unrinsed rinsable beans
                    s.system.silo.unripeSettings[C.UNRIPE_BEAN].balanceOfUnderlying; // unchopped underlying beans
                for (uint256 j; j < s.system.fieldCount; j++) {
                    entitlements[i] += (s.system.fields[j].harvestable -
                        s.system.fields[j].harvested); // unharvested harvestable beans
                }
            } else if (tokens[i] == LibUnripe._getUnderlyingToken(C.UNRIPE_LP)) {
                entitlements[i] += s.system.silo.unripeSettings[C.UNRIPE_LP].balanceOfUnderlying;
            }
            if (s.system.sopWell != address(0) && tokens[i] == address(LibSilo.getSopToken())) {
                entitlements[i] += s.system.plenty;
            }
            balances[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        return (entitlements, balances);
    }
}
