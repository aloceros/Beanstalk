// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Weather, C} from "./Weather.sol";
import {LibIncentive} from "contracts/libraries/LibIncentive.sol";
import {LibTransfer} from "contracts/libraries/Token/LibTransfer.sol";
import {LibWell} from "contracts/libraries/Well/LibWell.sol";
import {LibGauge} from "contracts/libraries/LibGauge.sol";
import {LibWhitelistedTokens} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";
import {LibGerminate} from "contracts/libraries/Silo/LibGerminate.sol";
import {Invariable} from "contracts/beanstalk/Invariable.sol";
import {LibTractor} from "contracts/libraries/LibTractor.sol";
import {LibRedundantMath256} from "contracts/libraries/LibRedundantMath256.sol";

/**
 * @title SeasonFacet
 * @author Publius, Chaikitty, Brean
 * @notice Holds the Sunrise function and handles all logic for Season changes.
 */
contract SeasonFacet is Invariable, Weather {
    using LibRedundantMath256 for uint256;

    /**
     * @notice Emitted when the Season changes.
     * @param season The new Season number
     */
    event Sunrise(uint256 indexed season);

    //////////////////// SUNRISE ////////////////////

    /**
     * @notice Advances Beanstalk to the next Season, sending reward Beans to the caller's circulating balance.
     * @return reward The number of beans minted to the caller.
     * @dev No out flow because any externally sent reward beans are freshly minted.
     */
    // TODO: FIx this. should be broken from noNetFlow bc balance of beanstalk will increase
    function sunrise() external payable fundsSafu noOutFlow returns (uint256) {
        return gm(LibTractor._user(), LibTransfer.To.EXTERNAL);
    }

    /**
     * @notice Advances Beanstalk to the next Season, sending reward Beans to a specified address & balance.
     * @param account Indicates to which address reward Beans should be sent
     * @param mode Indicates whether the reward beans are sent to internal or circulating balance
     * @return reward The number of Beans minted to the caller.
     * @dev No out flow because any externally sent reward beans are freshly minted.
     */
    function gm(
        address account,
        LibTransfer.To mode
    ) public payable fundsSafu noOutFlow returns (uint256) {
        uint256 initialGasLeft = gasleft();

        require(!s.paused, "Season: Paused.");
        require(seasonTime() > s.season.current, "Season: Still current Season.");
        uint32 season = stepSeason();
        int256 deltaB = stepOracle();
        uint256 caseId = calcCaseIdandUpdate(deltaB);
        LibGerminate.endTotalGermination(season, LibWhitelistedTokens.getWhitelistedTokens());
        LibGauge.stepGauge();
        stepSun(deltaB, caseId);

        return incentivize(account, initialGasLeft, mode);
    }

    /**
     * @notice Returns the expected Season number given the current block timestamp.
     * {sunrise} can be called when `seasonTime() > s.season.current`.
     */
    function seasonTime() public view virtual returns (uint32) {
        if (block.timestamp < s.season.start) return 0;
        if (s.season.period == 0) return type(uint32).max;
        return uint32((block.timestamp - s.season.start) / s.season.period);
    }

    //////////////////// SEASON INTERNAL ////////////////////

    /**
     * @dev Moves the Season forward by 1.
     */
    function stepSeason() private returns (uint32 season) {
        s.season.current += 1;
        season = s.season.current;
        s.season.sunriseBlock = uint32(block.number); // Note: Will overflow in the year 3650.
        emit Sunrise(season);
    }

    /**
     * @param account The address to which the reward beans are sent, may or may not
     * be the same as the caller of `sunrise()`
     * @param mode Send reward beans to Internal or Circulating balance
     * @dev Mints Beans to `account` as a reward for calling {sunrise()}.
     */
    function incentivize(address account, LibTransfer.To mode) private returns (uint256) {
        // Number of blocks the sunrise is late by
        // Assumes that each block timestamp is exactly `C.BLOCK_LENGTH_SECONDS` apart.
        uint256 blocksLate = block.timestamp.sub(
            s.season.start.add(s.season.period.mul(s.season.current))
        );

        // Read the Bean / Eth price calculated by the Minting Well.
        uint256 beanEthPrice = LibWell.getWellPriceFromTwaReserves(C.BEAN_ETH_WELL);

        // reset USD Token prices and TWA reserves in storage for all whitelisted Well LP Tokens.
        address[] memory whitelistedWells = LibWhitelistedTokens.getWhitelistedWellLpTokens();
        for (uint256 i; i < whitelistedWells.length; i++) {
            LibWell.resetUsdTokenPriceForWell(whitelistedWells[i]);
            LibWell.resetTwaReservesForWell(whitelistedWells[i]);
        }

        uint256 incentiveAmount = LibIncentive.determineReward(blocksLate);

        LibTransfer.mintToken(C.bean(), incentiveAmount, account, mode);

        emit LibIncentive.Incentivization(account, incentiveAmount);
        return incentiveAmount;
    }
}
