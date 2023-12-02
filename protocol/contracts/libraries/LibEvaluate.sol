// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import {LibAppStorage, AppStorage} from "./LibAppStorage.sol";
import {Decimal, SafeMath} from "contracts/libraries/Decimal.sol";
import {LibWhitelistedTokens, C} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";
import {LibBeanMetaCurve} from "contracts/libraries/Curve/LibBeanMetaCurve.sol";
import {LibUnripe} from "contracts/libraries/LibUnripe.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibSafeMath32} from "contracts/libraries/LibSafeMath32.sol";
import {LibWell} from "contracts/libraries/Well/LibWell.sol";

/**
 * @author Brean
 * @title LibEvaluate calculates the caseId based on the state of Beanstalk.
 * @dev the current parameters that beanstalk uses to evaluate its state are:
 * - DeltaB, the amount of Beans needed to be bought/sold to reach peg.
 * - PodRate, the ratio of Pods outstanding against the bean supply.
 * - Delta Soil demand, the change in demand of Soil between the current and previous Season.
 * - LpToSupplyRatio (L2SR), the ratio of liquidity to the circulating Bean supply.
 *
 * based on the caseId, Beanstalk adjusts:
 * - the Temperature
 * - the ratio of the gaugePoints per BDV of bean and the largest GpPerBdv for a given LP token. 
 */

library DecimalExtended {
    uint256 private constant PERCENT_BASE = 1e18;

    function toDecimal(uint256 a) internal pure returns (Decimal.D256 memory) {
        return Decimal.D256({ value: a });
    }
}

library LibEvaluate {
    using SafeMath for uint256;
    using DecimalExtended for uint256;
    using Decimal for Decimal.D256;
    using LibSafeMath32 for uint32;

    // Pod rate bounds
    uint256 internal constant POD_RATE_LOWER_BOUND = 0.05e18; // 5%
    uint256 internal constant POD_RATE_OPTIMAL = 0.15e18; // 15%
    uint256 internal constant POD_RATE_UPPER_BOUND = 0.25e18; // 25%

    // Change in Soil demand bounds
    uint256 internal constant DELTA_POD_DEMAND_LOWER_BOUND = 0.95e18; // 95%
    uint256 internal constant DELTA_POD_DEMAND_UPPER_BOUND = 1.05e18; // 105%

    /// @dev If all Soil is Sown faster than this, Beanstalk considers demand for Soil to be increasing.
    uint256 internal constant SOW_TIME_DEMAND_INCR = 600; // seconds

    uint32 internal constant SOW_TIME_STEADY = 60; // seconds

    // Liquidity to supply ratio bounds
    uint256 internal constant LP_TO_SUPPLY_RATIO_UPPER_BOUND = 0.8e18; // 80%
    uint256 internal constant LP_TO_SUPPLY_RATIO_OPTIMAL = 0.4e18; // 40%
    uint256 internal constant LP_TO_SUPPLY_RATIO_LOWER_BOUND = 0.12e18; // 12%

    // Excessive price threshold constant
    uint256 internal constant EXCESSIVE_PRICE_THRESHOLD = 1.05e6;

    uint256 internal constant LIQUIDITY_PRECISION = 1e12;

    /**
     * @notice evaluates the pod rate and returns the caseId
     * @param podRate the length of the podline (debt), divided by the bean supply.
     */
    function evalPodRate(Decimal.D256 memory podRate) internal pure returns (uint256 caseId) {
        if (podRate.greaterThanOrEqualTo(POD_RATE_UPPER_BOUND.toDecimal())) {
            caseId = 27;
        } else if (podRate.greaterThanOrEqualTo(POD_RATE_OPTIMAL.toDecimal())) {
            caseId = 18;
        } else if (podRate.greaterThanOrEqualTo(POD_RATE_LOWER_BOUND.toDecimal())) {
            caseId = 9;
        }
    }

    /**
     * @notice updates the caseId based on the price of bean (deltaB)
     * @param deltaB the amount of beans needed to be sold or bought to get bean to peg.
     * @param podRate the length of the podline (debt), divided by the bean supply.
     */
    function evalPrice(
        int256 deltaB,
        Decimal.D256 memory podRate
    ) internal view returns (uint256 caseId) {
        // p > 1
        if (
            deltaB > 0 || (deltaB == 0 && podRate.lessThanOrEqualTo(POD_RATE_OPTIMAL.toDecimal()))
        ) {
            // Beanstalk will only use the Bean/Eth well to compute the Bean price,
            // and thus will skip the p > EXCESSIVE_PRICE_THRESHOLD check if the Bean/Eth oracle fails to
            // compute a valid price this Season.
            uint256 beanEthPrice = LibWell.getWellPriceFromTwaReserves(C.BEAN_ETH_WELL);
            if (beanEthPrice > 1) {
                uint256 beanUsdPrice = LibWell.getUsdTokenPriceForWell(C.BEAN_ETH_WELL)
                    .mul(beanEthPrice)
                    .div(1e18);
                if (beanUsdPrice > EXCESSIVE_PRICE_THRESHOLD) {
                    // p > EXCESSIVE_PRICE_THRESHOLD
                    return caseId = 6;
                }
            }
            caseId = 3;
        }
        // p < 1
    }

    /**
     * @notice Updates the caseId based on the change in Soil demand.
     * @param deltaPodDemand The change in Soil demand from the previous Season.
     */
    function evalDeltaPodDemand(
        Decimal.D256 memory deltaPodDemand
    ) internal pure returns (uint256 caseId) {
        // increasing
        if (deltaPodDemand.greaterThanOrEqualTo(DELTA_POD_DEMAND_UPPER_BOUND.toDecimal())) {
            caseId = 2;
        // steady
        } else if (deltaPodDemand.greaterThanOrEqualTo(DELTA_POD_DEMAND_LOWER_BOUND.toDecimal())) {
            caseId = 1;
        }
        // decreasing (caseId = 0)
    }

    /**
     * @notice Evaluates the lp to supply ratio and returns the caseId.
     * @param lpToSupplyRatio The ratio of liquidity to supply.
     * 
     * @dev 'liquidity' is definied as the non-bean value in a pool that trades beans.
     */
    function evalLpToSupplyRatio(
        Decimal.D256 memory lpToSupplyRatio
    ) internal pure returns (uint256 caseId) {
        // Extremely High
        if (lpToSupplyRatio.greaterThanOrEqualTo(LP_TO_SUPPLY_RATIO_UPPER_BOUND.toDecimal())) {
            caseId = 108;
        // Reasonably High
        } else if (lpToSupplyRatio.greaterThanOrEqualTo(LP_TO_SUPPLY_RATIO_OPTIMAL.toDecimal())) {
            caseId = 72;
        // Reasonably Low
        } else if (
            lpToSupplyRatio.greaterThanOrEqualTo(LP_TO_SUPPLY_RATIO_LOWER_BOUND.toDecimal())
        ) {
            caseId = 36;
        }
        // excessively low (caseId = 0)
    }

    /**
     * @notice Calculates the change in soil demand from the previous season.
     * @param dsoil The amount of soil sown this season.
     */
    function calcDeltaPodDemand(
        uint256 dsoil
    )
        internal
        view
        returns (Decimal.D256 memory deltaPodDemand, uint32 lastSowTime, uint32 thisSowTime)
    {
        AppStorage storage s = LibAppStorage.diamondStorage();

        // `s.w.thisSowTime` is set to the number of seconds in it took for
        // Soil to sell out during the current Season. If Soil didn't sell out,
        // it remains `type(uint32).max`.
        if (s.w.thisSowTime < type(uint32).max) {
            if (
                s.w.lastSowTime == type(uint32).max || // Didn't Sow all last Season
                s.w.thisSowTime < SOW_TIME_DEMAND_INCR || // Sow'd all instantly this Season
                (s.w.lastSowTime > SOW_TIME_STEADY &&
                    s.w.thisSowTime < s.w.lastSowTime.sub(SOW_TIME_STEADY)) // Sow'd all faster
            ) {
                deltaPodDemand = Decimal.from(1e18);
            } else if (s.w.thisSowTime <= s.w.lastSowTime.add(SOW_TIME_STEADY)) {
                // Sow'd all in same time
                deltaPodDemand = Decimal.one();
            } else {
                deltaPodDemand = Decimal.zero();
            }
        } else {
            // Soil didn't sell out
            uint256 lastDSoil = s.w.lastDSoil;

            if (dsoil == 0) {
                deltaPodDemand = Decimal.zero(); // If no one Sow'd
            } else if (lastDSoil == 0) {
                deltaPodDemand = Decimal.from(1e18); // If no one Sow'd last Season
            } else {
                deltaPodDemand = Decimal.ratio(dsoil, lastDSoil);
            }
        }

        lastSowTime = s.w.thisSowTime; // Overwrite last Season
        thisSowTime = type(uint32).max; // Reset for next Season
    }

    /**
     * @notice Calculates the liquidity to supply ratio, where liquidity is measured in USD.
     * @param beanSupply The total supply of Beans.
     * corresponding to the well addresses in the whitelist.
     * @dev No support for non-well AMMs at this time.
     */
    function calcLPToSupplyRatio(
        uint256 beanSupply
    ) internal view returns (Decimal.D256 memory lpToSupplyRatio) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        // prevent infinite L2SR
        if (beanSupply == 0) return Decimal.zero();

        address[] memory pools = LibWhitelistedTokens.getWhitelistedLpTokens();
        uint256[] memory twaReserves;
        uint256 usdLiquidity;
        for (uint256 i; i < pools.length; i++) {
            // get the liquidity weight.
            uint256 liquidityWeight = getLiquidityWeight(s.ss[pools[i]].lwSelector);
            
            // get the non-bean value in an LP.
            twaReserves = LibWell.getTwaReservesFromStorageOrBeanstalkPump(
                pools[i]
            );

            usdLiquidity = usdLiquidity.add(
                liquidityWeight.mul(LibWell.getWellTwaUsdLiquidityFromReserves(pools[i], twaReserves)).div(1e18)
            );
            
            if (pools[i] == C.BEAN_ETH_WELL) {
                // Scale down bean supply by the locked beans, if there is fertilizer to be paid off.
                // Note: This statement is put into the for loop to prevent another extraneous read of 
                // the twaReserves from storage as `twaReserves` are already loaded into memory.
                if (LibAppStorage.diamondStorage().season.fertilizing == true) {
                    beanSupply = beanSupply.sub(LibUnripe.getLockedBeans(twaReserves));
                }
            }
            
            // If a new non-Well LP is added, functionality to calculate the USD value of the 
            // liquidity should be added here.
        }

        // if there is no liquidity,
        // return 0 to save gas.
        if (usdLiquidity == 0) return Decimal.zero();

        // USD liquidity is scaled down from 1e18 to match Bean precision (1e6).
        lpToSupplyRatio = Decimal.ratio(usdLiquidity.div(LIQUIDITY_PRECISION), beanSupply);
    }

    /**
     * @notice Get the deltaPodDemand, lpToSupplyRatio, and podRate, and update soil demand
     * parameters.
     */
    function getBeanstalkState(
        uint256 beanSupply
    )
        internal
        returns (
            Decimal.D256 memory deltaPodDemand,
            Decimal.D256 memory lpToSupplyRatio,
            Decimal.D256 memory podRate
        )
    {
        AppStorage storage s = LibAppStorage.diamondStorage();
        // Calculate Delta Soil Demand
        uint256 dsoil = s.f.beanSown;
        s.f.beanSown = 0;
        (deltaPodDemand, s.w.lastSowTime, s.w.thisSowTime) = calcDeltaPodDemand(dsoil);
        s.w.lastDSoil = uint128(dsoil); // SafeCast not necessary as `s.f.beanSown` is uint128.

        // Calculate Lp To Supply Ratio, fetching the twaReserves in storage:
        lpToSupplyRatio = calcLPToSupplyRatio(
            beanSupply
        );

        // Calculate PodRate
        podRate = Decimal.ratio(s.f.pods.sub(s.f.harvestable), beanSupply); // Pod Rate
    }

    /**
     * @notice Evaluates beanstalk based on deltaB, podRate, deltaPodDemand and lpToSupplyRatio.
     * and returns the associated caseId.
     */
    function evaluateBeanstalk(
        int256 deltaB,
        uint256 beanSupply
    ) internal returns (uint256 caseId) {
        (
            Decimal.D256 memory deltaPodDemand,
            Decimal.D256 memory lpToSupplyRatio,
            Decimal.D256 memory podRate
        ) = getBeanstalkState(beanSupply);
        caseId = evalPodRate(podRate) // Evaluate Pod Rate
        .add(evalPrice(deltaB, podRate)) // Evaluate Price
        .add(evalDeltaPodDemand(deltaPodDemand)) // Evaluate Delta Soil Demand 
        .add(evalLpToSupplyRatio(lpToSupplyRatio)); // Evaluate LP to Supply Ratio
    }

    /**
     * @notice calculates the liquidity weight of a token.
     * @dev the liquidity weight determines the percentage of
     * liquidity is considered in evaluating the liquidity of bean.
     * At 0, no liquidity is added. at 1e18, all liquidity is added.
     * 
     * if failure, returns 0 (no liquidity is considered) instead of reverting.
     */
    function getLiquidityWeight(
        bytes4 lwSelector
    ) internal view returns (uint256 liquidityWeight) {
        bytes memory callData = abi.encodeWithSelector(lwSelector);
        (bool success, bytes memory data) = address(this).staticcall(callData);
        if (!success) {
            return 0;
        }
        assembly {
            liquidityWeight := mload(add(data, add(0x20, 0)))
        }
    }
}
