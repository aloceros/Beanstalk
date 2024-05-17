// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LibEvaluate} from "contracts/libraries/LibEvaluate.sol";
import {LibRedundantMath128} from "contracts/libraries/LibRedundantMath128.sol";
import {LibCases} from "contracts/libraries/LibCases.sol";
import {Sun, C} from "./Sun.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBeanstalkWellFunction} from "contracts/interfaces/basin/IBeanstalkWellFunction.sol";
import {LibWell} from "contracts/libraries/Well/LibWell.sol";
import {IWell, Call} from "contracts/interfaces/basin/IWell.sol";
import {IInstantaneousPump} from "contracts/interfaces/basin/pumps/IInstantaneousPump.sol";
// import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {LibWhitelistedTokens} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";
// import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {LibWellMinting} from "contracts/libraries/Minting/LibWellMinting.sol";
import {console} from "forge-std/console.sol";
import {LibRedundantMath256} from "contracts/libraries/LibRedundantMath256.sol";
import {LibRedundantMathSigned256} from "contracts/libraries/LibRedundantMathSigned256.sol";

/**
 * @title Weather
 * @author Publius
 * @notice Weather controls the Temperature and Grown Stalk to LP on the Farm.
 */
contract Weather is Sun {
    using LibRedundantMath256 for uint256;
    using LibRedundantMathSigned256 for int256;
    using LibRedundantMath128 for uint128;

    uint128 internal constant MAX_BEAN_LP_GP_PER_BDV_RATIO = 100e18;

    uint256 internal constant FLOOD_PODLINE_PERCENT_DENOMINATOR = 1000;

    struct WellDeltaB {
        address well;
        int256 deltaB; // reviewer note: worth squishing these into one slot?
        uint256 reductionAmount;
    }

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
     * @notice Emitted when Beans are minted to a Well during the Season of Plenty.
     * @param season The Season in which Beans were minted for distribution.
     * @param well The Well that the SOP occurred in.
     * @param token The token that was swapped for Beans.
     * @param amount The amount of tokens which was received for swapping Beans.
     */
    event SeasonOfPlentyWell(uint256 indexed season, address well, address token, uint256 amount);

    /**
     * @notice Emitted when Beans are minted to the Field during the Season of Plenty.
     * @param toField The amount of Beans which were distributed to remaining Pods in the Field.
     */
    event SeasonOfPlentyField(uint256 toField);

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
            if (t <= uint256(int256(-bT))) {
                // if (change < 0 && t <= uint32(-change)),
                // then 0 <= t <= type(int8).max because change is an int8.
                // Thus, downcasting t to an int8 will not cause overflow.
                bT = 1 - int8(int256(t));
                s.w.t = 1;
            } else {
                s.w.t = uint32(t - uint256(int256(-bT)));
            }
        } else {
            s.w.t = uint32(t + uint256(int256(bT)));
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
            if (beanToMaxLpGpPerBdvRatio <= uint128(int128(-bL))) {
                bL = -SafeCast.toInt80(int256(uint256(beanToMaxLpGpPerBdvRatio)));
                s.seedGauge.beanToMaxLpGpPerBdvRatio = 0;
            } else {
                s.seedGauge.beanToMaxLpGpPerBdvRatio = beanToMaxLpGpPerBdvRatio.sub(
                    uint128(int128(-bL))
                );
            }
        } else {
            if (beanToMaxLpGpPerBdvRatio.add(uint128(int128(bL))) >= MAX_BEAN_LP_GP_PER_BDV_RATIO) {
                // if (change > 0 && 100e18 - beanToMaxLpGpPerBdvRatio <= bL),
                // then bL cannot overflow.
                bL = int80(
                    SafeCast.toInt80(
                        int256(uint256(MAX_BEAN_LP_GP_PER_BDV_RATIO.sub(beanToMaxLpGpPerBdvRatio)))
                    )
                );
                s.seedGauge.beanToMaxLpGpPerBdvRatio = MAX_BEAN_LP_GP_PER_BDV_RATIO;
            } else {
                s.seedGauge.beanToMaxLpGpPerBdvRatio = beanToMaxLpGpPerBdvRatio.add(
                    uint128(int128(bL))
                );
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
            // flood podline first, because it checks current Bean supply
            floodPodline();

            if (s.r.roots > 0) {
                WellDeltaB[] memory wellDeltaBs = getWellsByDeltaB();
                wellDeltaBs = calculateSopPerWell(wellDeltaBs);

                for (uint i; i < wellDeltaBs.length; i++) {
                    sop(wellDeltaBs[i]);
                }
            }
        }
    }

    function floodPodline() private {
        // Make 0.1% of the total bean supply worth of pods harvestable.

        uint256 totalBeanSupply = C.bean().totalSupply();
        uint256 sopFieldBeans = totalBeanSupply.div(FLOOD_PODLINE_PERCENT_DENOMINATOR); // 1/1000 = 0.1% of total supply

        // Note there may be cases where zero harvestable pods are available. For clarity, the code will still emit an event
        // but with zero sop field beans.
        uint256 maxHarvestable = s.f.pods.sub(s.f.harvestable);
        sopFieldBeans = sopFieldBeans > maxHarvestable ? maxHarvestable : sopFieldBeans;

        s.f.harvestable = s.f.harvestable.add(sopFieldBeans);
        C.bean().mint(address(this), sopFieldBeans);

        emit SeasonOfPlentyField(sopFieldBeans);
    }

    function getWellsByDeltaB() public view returns (WellDeltaB[] memory) {
        address[] memory wells = LibWhitelistedTokens.getWhitelistedWellLpTokens();
        WellDeltaB[] memory wellDeltaBs = new WellDeltaB[](wells.length);
        for (uint i = 0; i < wells.length; i++) {
            wellDeltaBs[i] = WellDeltaB(wells[i], LibWellMinting.cappedReservesDeltaB(wells[i]), 0);
        }

        // Sort the wellDeltaBs array
        quickSort(wellDeltaBs, 0, int(wellDeltaBs.length - 1));

        return wellDeltaBs;
    }

    // Reviewer note: This works, but there's got to be a way to make this more gas efficient
    function quickSort(
        WellDeltaB[] memory arr,
        int left,
        int right
    ) public pure returns (WellDeltaB[] memory) {
        if (left >= right) return arr;

        // Choose the median of left, right, and middle as pivot (improves performance on random data)
        uint mid = uint(left) + (uint(right) - uint(left)) / 2;
        WellDeltaB memory pivot = arr[uint(left)].deltaB > arr[uint(mid)].deltaB
            ? (
                arr[uint(left)].deltaB < arr[uint(right)].deltaB
                    ? arr[uint(left)]
                    : arr[uint(right)]
            )
            : (arr[uint(mid)].deltaB < arr[uint(right)].deltaB ? arr[uint(mid)] : arr[uint(right)]);

        int i = left;
        int j = right;
        while (i <= j) {
            while (arr[uint(i)].deltaB > pivot.deltaB) i++;
            while (pivot.deltaB > arr[uint(j)].deltaB) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }

        if (left < j) {
            return quickSort(arr, left, j);
        }
        if (i < right) {
            return quickSort(arr, i, right);
        }
        return arr;
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
    function sop(WellDeltaB memory wellDeltaB) private {
        if (wellDeltaB.reductionAmount == 0) return;
        IERC20 sopToken = LibWell.getNonBeanTokenFromWell(wellDeltaB.well);

        uint256 sopBeans = wellDeltaB.reductionAmount;

        // code reviewer note: pre-calc total amount of beans to mint and mint them all at once?
        C.bean().mint(address(this), sopBeans);

        // Approve and Swap Beans for the non-bean token of the SOP well.
        C.bean().approve(wellDeltaB.well, sopBeans);
        uint256 amountOut = IWell(wellDeltaB.well).swapFrom(
            C.bean(),
            sopToken,
            sopBeans,
            0,
            address(this),
            type(uint256).max
        );
        s.plenty += amountOut;
        rewardSop(wellDeltaB.well, amountOut);
        emit SeasonOfPlentyWell(s.season.current, wellDeltaB.well, address(sopToken), amountOut);
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

    /*
     * @notice Calculates the amount of beans per well that should be minted in a sop.
     * @param wellDeltaBs The deltaBs of all whitelisted wells in which to flood. Must be sorted in descending order.
     */
    // code review note: have some casual comments here for just understanding the code, happy to
    // change this function to make it more efficient based on feedback.
    function calculateSopPerWell(
        WellDeltaB[] memory wellDeltaBs
    ) public pure returns (WellDeltaB[] memory) {
        uint256 totalPositiveDeltaB = 0;
        uint256 totalNegativeDeltaB = 0;
        uint256 positiveDeltaBCount = 0;

        for (uint256 i = 0; i < wellDeltaBs.length; i++) {
            if (wellDeltaBs[i].deltaB > 0) {
                totalPositiveDeltaB += uint256(wellDeltaBs[i].deltaB);
                positiveDeltaBCount++;
            } else {
                totalNegativeDeltaB += uint256(-wellDeltaBs[i].deltaB);
            }
        }

        // most likely case is that all deltaBs are positive
        if (positiveDeltaBCount == wellDeltaBs.length) {
            // if all deltaBs are positive, need to sop all to zero
            for (uint256 i = 0; i < wellDeltaBs.length; i++) {
                wellDeltaBs[i].reductionAmount = uint256(wellDeltaBs[i].deltaB);
            }
            return wellDeltaBs;
        }

        if (positiveDeltaBCount == 0) {
            // No positive values, so no well flooding needed
            return wellDeltaBs;
        }

        if (totalPositiveDeltaB < totalNegativeDeltaB) {
            // in theory this should never happen because overall deltaB is required for sop
            revert("Flood: Overall deltaB is negative");
        }

        uint256 shaveOff = totalPositiveDeltaB - totalNegativeDeltaB;
        uint256 cumulativeTotal;
        uint256 shaveToLevel;

        for (uint256 i = 0; i <= positiveDeltaBCount; i++) {
            if (positiveDeltaBCount == 1 || i == 0) {
                // reduce enough to equal the negative deltaB
                if (positiveDeltaBCount == 1) {
                    wellDeltaBs[i].reductionAmount = uint256(wellDeltaBs[i].deltaB).sub(
                        totalNegativeDeltaB
                    );
                    return wellDeltaBs;
                }
            } else {
                uint256 diffToPrevious = wellDeltaBs[i].deltaB > 0
                    ? uint256(wellDeltaBs[i - 1].deltaB).sub(uint256(wellDeltaBs[i].deltaB))
                    : 0;

                if (
                    cumulativeTotal.add(diffToPrevious.mul(i)) >= shaveOff ||
                    i == positiveDeltaBCount
                ) {
                    // There is enough to shave off using the already processed wells
                    // No need to dip into this one currently processing
                    uint256 remaining = shaveOff - cumulativeTotal;
                    // The remaining needs to be distributed equally taken from all the wells processed
                    // this proportional reduction can be used to subtract from the current well deltaB and find the shave-to level
                    shaveToLevel = uint(wellDeltaBs[i - 1].deltaB) - remaining.div(i);
                    break;
                } else {
                    cumulativeTotal = cumulativeTotal.add(diffToPrevious.mul(i));
                }
            }
        }

        // return the amount of beans that need to be flooded per well
        for (uint256 i = 0; i < positiveDeltaBCount; i++) {
            wellDeltaBs[i].reductionAmount = wellDeltaBs[i].deltaB > int256(shaveToLevel)
                ? uint256(wellDeltaBs[i].deltaB) - shaveToLevel
                : 0;
        }
        return wellDeltaBs;
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
        if (well == address(0)) return (0, IERC20(address(0)));
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
        if (!success) return (0, IERC20(address(0)));

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
        if (lowestSopBeans < 0) return (0, IERC20(address(0)));

        // SafeCast not necessary due to above check.
        sopBeans = uint256(lowestSopBeans);

        // the sopToken is the non bean token in the well.
        sopToken = tokens[beanIndex == 0 ? 1 : 0];
    }
}
