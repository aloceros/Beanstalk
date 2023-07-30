// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "contracts/libraries/Token/LibTransfer.sol";
import "contracts/libraries/LibIncentive.sol";
import "./Weather.sol";
import "contracts/libraries/Silo/LibWhitelist.sol";

/**
 * @title SeasonFacet
 * @author Publius, Chaikitty
 * @notice Holds the Sunrise function and handles all logic for Season changes.
 */
contract SeasonFacet is Weather {
    using SafeMath for uint256;

    uint256 private constant TARGET_SEASONS_TO_CATCHUP = 4380;
    /**
     * @notice Emitted when the Season changes.
     * @param season The new Season number
     */
    event Sunrise(uint256 indexed season);

    /**
     * @notice Emitted when Beanstalk pays `beans` to `account` as a reward for calling `sunrise()`.
     * @param account The address to which the reward Beans were sent
     * @param beans The amount of Beans paid as a reward
     */
    event Incentivization(address indexed account, uint256 beans);

    //////////////////// SUNRISE ////////////////////

    /**
     * @notice Advances Beanstalk to the next Season, sending reward Beans to the caller's circulating balance.
     * @return reward The number of beans minted to the caller.
     */
    function sunrise() external payable returns (uint256) {
        return gm(msg.sender, LibTransfer.To.EXTERNAL);
    }

    /**
     * @notice Advances Beanstalk to the next Season, sending reward Beans to a specified address & balance.
     * @param account Indicates to which address reward Beans should be sent
     * @param mode Indicates whether the reward beans are sent to internal or circulating balance
     * @return reward The number of Beans minted to the caller.
     */
    function gm(
        address account,
        LibTransfer.To mode
    ) public payable returns (uint256) {
        uint256 initialGasLeft = gasleft();

        require(!s.paused, "Season: Paused.");
        require(seasonTime() > s.season.current, "Season: Still current Season.");

        stepSeason();
        int256 deltaB = stepOracle();
        uint256 caseId = calcCaseId(deltaB);
        updateLPGaugeSystem(caseId);
        updateGrownStalkEarnedPerSeason();
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
        return uint32((block.timestamp - s.season.start) / s.season.period); // Note: SafeMath is redundant here.
    }

    //////////////////// SEASON INTERNAL ////////////////////

    /**
     * @dev Moves the Season forward by 1.
     */
    function stepSeason() private {
        s.season.current += 1;
        s.season.sunriseBlock = uint32(block.number); // Note: Will overflow in the year 3650.
        emit Sunrise(s.season.current);
    }

    /**
     * @param account The address to which the reward beans are sent, may or may not
     * be the same as the caller of `sunrise()`
     * @param initialGasLeft The amount of gas left at the start of the transaction
     * @param mode Send reward beans to Internal or Circulating balance
     * @dev Mints Beans to `account` as a reward for calling {sunrise()}.
     */
    function incentivize(
        address account,
        uint256 initialGasLeft,
        LibTransfer.To mode
    ) private returns (uint256) {
        // Number of blocks the sunrise is late by
        // Assumes that each block timestamp is exactly `C.BLOCK_LENGTH_SECONDS` apart.
        uint256 blocksLate = block.timestamp.sub(
            s.season.start.add(s.season.period.mul(s.season.current))
        )
        .div(C.BLOCK_LENGTH_SECONDS);
        
        uint256 incentiveAmount = LibIncentive.determineReward(initialGasLeft, blocksLate);

        LibTransfer.mintToken(C.bean(), incentiveAmount, account, mode);
        
        emit Incentivization(account, incentiveAmount);
        return incentiveAmount;
    }

    //////////////////// SEED GAUGE INTERNAL ////////////////////

    /**
     * @notice Updates the average grown stalk per BDV per Season for whitelisted Beanstalk assets.
     * @dev Called at the end of each Season.
     */
    function updateGrownStalkEarnedPerSeason() internal {
        // Assume percentOfSeedsToLP has 6 decimal precision
        uint256 newGrownStalk = s.seedGauge.averageGrownStalkPerBdvPerSeason * s.seedGauge.totalBdv;
        uint256 newGrownStalkToLP = newGrownStalk * s.seedGauge.percentOfNewGrownStalkToLP / 1e6;
        uint256 newGrownStalkToBean = newGrownStalk - newGrownStalkToLP;

        // update stalkPerBDVPerSeason for bean
        if(getDepositedBdvForToken(C.BEAN) > 0){
            LibWhitelist.updateStalkPerBdvPerSeasonForToken(
                C.BEAN,
                uint24(newGrownStalkToBean.div(getDepositedBdvForToken(C.BEAN)))
            );
        }

        // update stalkPerBdvPerSeason for LP 
        // for 1 LP pool, no need for seed LP distrubution (BEAN:ETH)
        if(getDepositedBdvForToken(C.BEAN_ETH_WELL) > 0){
            LibWhitelist.updateStalkPerBdvPerSeasonForToken(
                C.BEAN_ETH_WELL,
                uint24(newGrownStalkToLP.div(getDepositedBdvForToken(C.BEAN_ETH_WELL)))
            );
        }
    }

    function updateLPGaugeSystem(uint256 caseId) internal {
        //TODO
    }

    /**
     * @notice Returns the amount of BDV deposited for a given token.
     * @param token The address of the token.
     * @return The amount of BDV deposited for the token.
     */
    function getDepositedBdvForToken(address token) internal view returns (uint256){
        return s.siloBalances[token].depositedBdv;
    }

    /**
     * @notice updates the averageGrownStaklPerBdvPerSeason 
     */
    function updateAverageGrownStalkPerBdv() external {
        uint256 averageGrownStalkPerBdv = s.s.stalk / s.seedGauge.totalBdv - 10000; // TODO: Check constant
        s.seedGauge.averageGrownStalkPerBdvPerSeason = uint96(averageGrownStalkPerBdv / TARGET_SEASONS_TO_CATCHUP);
    }

}
