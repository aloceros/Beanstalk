// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import {LibEvaluate} from "contracts/libraries/LibEvaluate.sol";
import {LibSafeMath128} from "contracts/libraries/LibSafeMath128.sol";
import {LibCases} from "contracts/libraries/LibCases.sol";
import {Sun, SafeMath, C} from "./Sun.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBeanstalkWellFunction} from "contracts/interfaces/basin/IBeanstalkWellFunction.sol";
import {LibWell} from "contracts/libraries/Well/LibWell.sol";
import {IWell, Call} from "contracts/interfaces/basin/IWell.sol";
import {IInstantaneousPump} from "contracts/interfaces/basin/pumps/IInstantaneousPump.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {LibWhitelistedTokens} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Weather
 * @author Publius
 * @notice Weather controls the Temperature and Grown Stalk to LP on the Farm.
 */
contract Weather is Sun {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using LibSafeMath128 for uint128;

    uint128 internal constant MAX_BEAN_LP_GP_PER_BDV_RATIO = 100e18;

    /**
     * @notice Emitted when the Temperature (fka "Weather") changes.
     * @param season The current Season
     * @param caseId The Weather case, which determines how much the Temperature is adjusted.
     * @param absChange The absolute change in Temperature.
     * @dev formula: T_n = T_n-1 +/- bT
     */
    event TemperatureChange(uint256 indexed season, uint256 caseId, int8 absChange);

    /**
     * @notice Emitted when the grownStalkToLP changes.
     * @param season The current Season
     * @param caseId The Weather case, which determines how the BeanToMaxLPGpPerBDVRatio is adjusted.
     * @param absChange The absolute change in the BeanToMaxLPGpPerBDVRatio.
     * @dev formula: L_n = L_n-1 +/- bL
     */
    event BeanToMaxLpGpPerBdvRatioChange(uint256 indexed season, uint256 caseId, int80 absChange);

    /**
     * @notice Emitted when Beans are minted during the Season of Plenty.
     * @param season The Season in which Beans were minted for distribution.
     * @param well The Well that the SOP occurred in.
     * @param token The token that was swapped for Beans.
     * @param amount The amount of 3CRV which was received for swapping Beans.
     * @param toField The amount of Beans which were distributed to remaining Pods in the Field.
     */
    event SeasonOfPlenty(
        uint256 indexed season,
        address well,
        address token,
        uint256 amount,
        uint256 toField
    );

    //////////////////// WEATHER INTERNAL ////////////////////

    /**
     * @notice from deltaB, podRate, change in soil demand, and liquidity to supply ratio,
     * calculate the caseId, and update the temperature and grownStalkPerBdvToLp.
     * @param deltaB Pre-calculated deltaB from {Oracle.stepOracle}.
     * @dev A detailed explanation of the temperature and grownStalkPerBdvToLp
     * mechanism can be found in the Beanstalk whitepaper.
     * An explanation of state variables can be found in {AppStorage}.
     */
    function calcCaseIdandUpdate(int256 deltaB) internal returns (uint256) {
        uint256 beanSupply = C.bean().totalSupply();
        // prevents infinite L2SR and podrate
        if (beanSupply == 0) {
            s.w.t = 1;
            return 9; // Reasonably low
        }
        // Calculate Case Id
        (uint256 caseId, ) = LibEvaluate.evaluateBeanstalk(deltaB, beanSupply);
        updateTemperatureAndBeanToMaxLpGpPerBdvRatio(caseId);
        handleRain(caseId);
        return caseId;
    }

    /**
     * @notice updates the temperature and BeanToMaxLpGpPerBdvRatio, based on the caseId.
     * @param caseId the state beanstalk is in, based on the current season.
     */
    function updateTemperatureAndBeanToMaxLpGpPerBdvRatio(uint256 caseId) internal {
        LibCases.CaseData memory cd = LibCases.decodeCaseData(caseId);
        updateTemperature(cd.bT, caseId);
        updateBeanToMaxLPRatio(cd.bL, caseId);
    }

    /**
     * @notice Changes the current Temperature `s.w.t` based on the Case Id.
     * @dev bT are set during edge cases such that the event emitted is valid.
     */
    function updateTemperature(int8 bT, uint256 caseId) private {
        uint256 t = s.w.t;
        if (bT < 0) {
            if (t <= uint256(-bT)) {
                // if (change < 0 && t <= uint32(-change)),
                // then 0 <= t <= type(int8).max because change is an int8.
                // Thus, downcasting t to an int8 will not cause overflow.
                bT = 1 - int8(t);
                s.w.t = 1;
            } else {
                s.w.t = uint32(t - uint256(-bT));
            }
        } else {
            s.w.t = uint32(t + uint256(bT));
        }

        emit TemperatureChange(s.season.current, caseId, bT);
    }

    /**
     * @notice Changes the grownStalkPerBDVPerSeason based on the CaseId.
     * @dev bL are set during edge cases such that the event emitted is valid.
     */
    function updateBeanToMaxLPRatio(int80 bL, uint256 caseId) private {
        uint128 beanToMaxLpGpPerBdvRatio = s.seedGauge.beanToMaxLpGpPerBdvRatio;
        if (bL < 0) {
            if (beanToMaxLpGpPerBdvRatio <= uint128(-bL)) {
                bL = -int80(beanToMaxLpGpPerBdvRatio);
                s.seedGauge.beanToMaxLpGpPerBdvRatio = 0;
            } else {
                s.seedGauge.beanToMaxLpGpPerBdvRatio = beanToMaxLpGpPerBdvRatio.sub(uint128(-bL));
            }
        } else {
            if (beanToMaxLpGpPerBdvRatio.add(uint128(bL)) >= MAX_BEAN_LP_GP_PER_BDV_RATIO) {
                // if (change > 0 && 100e18 - beanToMaxLpGpPerBdvRatio <= bL),
                // then bL cannot overflow.
                bL = int80(MAX_BEAN_LP_GP_PER_BDV_RATIO.sub(beanToMaxLpGpPerBdvRatio));
                s.seedGauge.beanToMaxLpGpPerBdvRatio = MAX_BEAN_LP_GP_PER_BDV_RATIO;
            } else {
                s.seedGauge.beanToMaxLpGpPerBdvRatio = beanToMaxLpGpPerBdvRatio.add(uint128(bL));
            }
        }

        emit BeanToMaxLpGpPerBdvRatioChange(s.season.current, caseId, bL);
    }

    /**
     * @dev Oversaturated was previously referred to as Raining and thus code
     * references mentioning Rain really refer to Oversaturation. If P > 1 and the
     * Pod Rate is less than 5%, the Farm is Oversaturated. If it is Oversaturated
     * for a Season, each Season in which it continues to be Oversaturated, it Floods.
     */
    function handleRain(uint256 caseId) internal {
        // cases % 36  3-8 represent the case where the pod rate is less than 5% and P > 1.
        if (caseId.mod(36) < 3 || caseId.mod(36) > 8) {
            if (s.season.raining) {
                s.season.raining = false;
            }
            return;
        } else if (!s.season.raining) {
            s.season.raining = true;
            address[] memory wells = LibWhitelistedTokens.getWhitelistedWellLpTokens();
            // Set the plenty per root equal to previous rain start.
            uint32 season = s.season.current;
            uint32 rainstartSeason = s.season.rainStart;
            for (uint i; i < wells.length; i++) {
                s.sops[season][wells[i]] = s.sops[rainstartSeason][wells[i]];
            }
            s.season.rainStart = s.season.current;
            s.r.pods = s.f.pods;
            s.r.roots = s.s.roots;
        } else {
            if (s.r.roots > 0) {
                address[] memory wells = LibWhitelistedTokens.getWhitelistedWellLpTokens();
                for (uint i; i < wells.length; i++) {
                    sop(wells[i]);
                }
            }
            floodPodline();
        }
    }

    function floodPodline() private {
        // uint256 sopBeans = uint256(newBeans);
        // uint256 newHarvestable;
        // TODO: if podline is 1% or less of total bean supply,
        // then make 0.1% of the total bean supply worth of pods harvestable.
        // Pay off remaining Pods if any exist.
        /*if (s.f.harvestable < s.r.pods) {
            newHarvestable = s.r.pods - s.f.harvestable;
            s.f.harvestable = s.f.harvestable.add(newHarvestable);
            C.bean().mint(address(this), newHarvestable.add(sopBeans));
        } else {
            C.bean().mint(address(this), sopBeans);
        }*/
    }

    /**
     * @dev Flood was previously called a "Season of Plenty" (SOP for short).
     * When Beanstalk has been Oversaturated for a Season, Beanstalk returns the
     * Bean price to its peg by minting additional Beans and selling them directly
     * on the sop well. Proceeds from the sale in the form of WETH are distributed to
     * Stalkholders at the beginning of a Season in proportion to their Stalk
     * ownership when the Farm became Oversaturated. Also, at the beginning of the
     * Flood, all Pods that were minted before the Farm became Oversaturated Ripen
     * and become Harvestable.
     * For more information On Oversaturation see {Weather.handleRain}.
     */
    function sop(address well) private {
        // calculate the beans from a sop.
        // sop beans uses the min of the current and instantaneous reserves of the sop well,
        // rather than the twaReserves in order to get bean back to peg.
        (uint256 newBeans, IERC20 sopToken) = calculateSop(well);
        if (newBeans == 0) return;

        uint256 sopBeans = uint256(newBeans);

        // TODO: pre-calc total amount of beans to mint and mint them all at once
        C.bean().mint(address(this), sopBeans);

        // Approve and Swap Beans for the non-bean token of the SOP well.
        C.bean().approve(well, sopBeans);
        uint256 amountOut = IWell(well).swapFrom(
            C.bean(),
            sopToken,
            sopBeans,
            0,
            address(this),
            type(uint256).max
        );
        s.plenty += amountOut;
        rewardSop(well, amountOut);
        // TODO: emit events, but because we have multiple wells, perhaps we need an event per well, and a separate event for harvest pods.
        // emit SeasonOfPlenty(s.season.current, well, address(sopToken), amountOut, newHarvestable);
    }

    /**
     * @dev Allocate `sop token` during a Season of Plenty.
     */
    function rewardSop(address well, uint256 amount) private {
        s.sops[s.season.rainStart][well] = s.sops[s.season.lastSop][well].add(
            amount.mul(C.SOP_PRECISION).div(s.r.roots)
        );
        s.season.lastSop = s.season.rainStart;
        s.season.lastSopSeason = s.season.current;
    }

    // reduce the deltaBs of positive wells to the same amount so that the total is zero, and return the amount by which each deltaB was reduced
    /*function calculateSopPerWell(int256[] wellDeltaBs) private view returns (uint256[] memory) {
        int256 totalDeltaB = 0;
        uint256 positiveDeltaB = 0;
        for (uint256 i = 0; i < wellDeltaBs.length; i++) {
            totalDeltaB += wellDeltaBs[i];
            if (wellDeltaBs[i] > 0) {
                positiveDeltaB += wellDeltaBs[i];
            }
        }

        // this means there were no negative deltaBs, so we need to reduce each one by the same amount so that the total is zero
        if (totalDeltaB == positiveDeltaB) {
            return wellDeltaBs;
        }

        // all the positive deltaBs need to be flooded to the same deltaB
    }*/

    /*function calculateSopPerWell(
        int256[] memory wellDeltaBs
    ) external view returns (uint256[] memory) {
        int256 totalDeltaB = 0;
        int256 totalPositiveDeltaB = 0;
        int256 totalNegativeDeltaB = 0;
        uint256 positiveDeltaBCount = 0;

        for (uint256 i = 0; i < wellDeltaBs.length; i++) {
            totalDeltaB += wellDeltaBs[i];
            if (wellDeltaBs[i] > 0) {
                totalPositiveDeltaB += wellDeltaBs[i];
                positiveDeltaBCount++;
            } else {
                totalNegativeDeltaB += wellDeltaBs[i];
            }
        }

        if (positiveDeltaBCount == 0) {
            // No positive values, return an array of zeros
            uint256[] memory reductionAmounts = new uint256[](wellDeltaBs.length);
            return reductionAmounts;
        }

        int256 targetPositiveDeltaB = -totalNegativeDeltaB / int256(positiveDeltaBCount);
        console.log("targetPositiveDeltaB: ");
        console.logInt(targetPositiveDeltaB);

        uint256[] memory reductionAmounts = new uint256[](wellDeltaBs.length);

        for (uint256 i = 0; i < wellDeltaBs.length; i++) {
            if (wellDeltaBs[i] > targetPositiveDeltaB) {
                reductionAmounts[i] = uint256(wellDeltaBs[i] - targetPositiveDeltaB);
                console.log("reductionAmounts[i]: ", reductionAmounts[i]);
            }
        }

        return reductionAmounts;
    }*/

    function calculateSopPerWell(
        int256[] memory wellDeltaBs
    ) external view returns (uint256[] memory) {
        uint256 totalPositiveDeltaB = 0;
        uint256 totalNegativeDeltaB = 0;
        uint256 positiveDeltaBCount = 0;

        for (uint256 i = 0; i < wellDeltaBs.length; i++) {
            if (wellDeltaBs[i] > 0) {
                totalPositiveDeltaB += uint256(wellDeltaBs[i]);
                positiveDeltaBCount++;
            } else {
                totalNegativeDeltaB += uint256(-wellDeltaBs[i]);
            }
        }

        if (positiveDeltaBCount == 0) {
            // No positive values, should never happen, revert (or don't revert because this prevents sunrise?)
            revert("Flood: No positive deltaB pools to flood");
        }

        if (totalPositiveDeltaB < totalNegativeDeltaB) {
            // in theory this should never happen because overall deltaB is required for sop
            revert("Flood: Overall deltaB is negative");
        }

        uint256 shaveOff = totalPositiveDeltaB - totalNegativeDeltaB;
        uint256 previousDeltaB;
        uint256 cumulativeTotal;
        uint256 shaveToLevel;

        uint256[] memory reductionAmounts = new uint256[](wellDeltaBs.length);

        for (uint256 i = 0; i <= positiveDeltaBCount; i++) {
            console.logInt(wellDeltaBs[i]);
            if (positiveDeltaBCount == 1 || i == 0) {
                previousDeltaB = uint256(wellDeltaBs[i]);
            } else {
                // regular loop where we already have previousDeltaB setup
                uint256 diffToPrevious = previousDeltaB - uint256(wellDeltaBs[i]);

                previousDeltaB = uint256(wellDeltaBs[i]);

                if (cumulativeTotal.add(diffToPrevious.mul(i)) >= shaveOff) {
                    // we have enough to shave off using the already processed wells
                    // no need to dip into this one we're currently processing
                    // just need to calculate what the shave to deltaB is

                    // calculate how much remaining we need to take to get the cumulativeTotal equal to shaveOff
                    uint256 remaining = shaveOff - cumulativeTotal;
                    // this remaining needs to be distributed equally taken from all the wells processed
                    uint256 proportionalReduction = remaining / i;

                    // this proportional reduction can be used to subtract from the current well and find the shave-to level
                    shaveToLevel = uint(wellDeltaBs[i - 1]) - proportionalReduction;
                    break;
                } else {
                    cumulativeTotal = cumulativeTotal.add(diffToPrevious.mul(i));
                }
            }
        }

        for (uint256 i = 0; i < positiveDeltaBCount; i++) {
            reductionAmounts[i] = wellDeltaBs[i] > int256(shaveToLevel)
                ? uint256(wellDeltaBs[i]) - shaveToLevel
                : 0;
        }

        return reductionAmounts;
    }

    /**
     * Calculates the amount of beans that should be minted in a sop.
     * @dev the instanteous EMA reserves are used rather than the twa reserves
     * as the twa reserves are not indiciative of the current deltaB in the pool.
     *
     * Generalized for a single well. Sop does not support multiple wells.
     */
    function calculateSop(address well) private view returns (uint256 sopBeans, IERC20 sopToken) {
        // if the sopWell was not initalized, the should not occur.
        if (well == address(0)) return (0, IERC20(0));
        IWell sopWell = IWell(well);
        IERC20[] memory tokens = sopWell.tokens();
        Call[] memory pumps = sopWell.pumps();
        IInstantaneousPump pump = IInstantaneousPump(pumps[0].target);
        uint256[] memory instantaneousReserves = pump.readInstantaneousReserves(
            well,
            pumps[0].data
        );
        uint256[] memory currentReserves = sopWell.getReserves();
        Call memory wellFunction = sopWell.wellFunction();
        (uint256[] memory ratios, uint256 beanIndex, bool success) = LibWell.getRatiosAndBeanIndex(
            tokens
        );
        // If the USD Oracle oracle call fails, the sop should not occur.
        // return 0 rather than revert to prevent sunrise from failing.
        if (!success) return (0, IERC20(0));

        // compare the beans at peg using the instantaneous reserves,
        // and the current reserves.
        uint256 instantaneousBeansAtPeg = IBeanstalkWellFunction(wellFunction.target)
            .calcReserveAtRatioSwap(instantaneousReserves, beanIndex, ratios, wellFunction.data);

        uint256 currentBeansAtPeg = IBeanstalkWellFunction(wellFunction.target)
            .calcReserveAtRatioSwap(currentReserves, beanIndex, ratios, wellFunction.data);

        // Calculate the signed Sop beans for the two reserves.
        int256 lowestSopBeans = int256(instantaneousBeansAtPeg).sub(
            int256(instantaneousReserves[beanIndex])
        );
        int256 currentSopBeans = int256(currentBeansAtPeg).sub(int256(currentReserves[beanIndex]));

        // Use the minimum of the two.
        if (lowestSopBeans > currentSopBeans) {
            lowestSopBeans = currentSopBeans;
        }

        // If the sopBeans is negative, the sop should not occur.
        if (lowestSopBeans < 0) return (0, IERC20(0));

        // SafeCast not necessary due to above check.
        sopBeans = uint256(lowestSopBeans);

        // the sopToken is the non bean token in the well.
        sopToken = tokens[beanIndex == 0 ? 1 : 0];
    }
}
