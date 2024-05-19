/*
 SPDX-License-Identifier: MIT
*/

pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import {AppStorage} from "contracts/beanstalk/AppStorage.sol";
import {LibCases} from "contracts/libraries/LibCases.sol";
import {C} from "contracts/C.sol";

/**
 * @author Brean
 * @notice ReseedSun re-initializes the sun.
 * @dev cases are re-initialized. Season is set to L1 state.
 */
contract ReseedSun {
    uint256 constant PERIOD = 3600;
    uint256 constant TIMESTAMP = 0;
    /**
     * @notice Emitted when the AverageGrownStalkPerBdvPerSeason Updates.
     */
    event UpdateAverageStalkPerBdvPerSeason(uint256 newStalkPerBdvPerSeason);

    /**
     * @notice Emitted when the grownStalkToLP changes.
     * @param season The current Season
     * @param caseId The Weather case, which determines how the BeanToMaxLPGpPerBDVRatio is adjusted.
     * @param absChange The absolute change in the BeanToMaxLPGpPerBDVRatio.
     * @dev formula: L_n = L_n-1 +/- bL
     */
    event BeanToMaxLpGpPerBdvRatioChange(uint256 indexed season, uint256 caseId, int80 absChange);

    AppStorage internal s;

    function init(
        uint32 season,
        uint32 temperature,
        uint128 averageGrownStalkPerBdvPerSeason,
        uint128 beanToMaxLpGpPerBdvRatio
    ) external {
        s.season.current = season;
        s.season.period = PERIOD;
        s.season.timestamp = TIMESTAMP;
        s.w.t = temperature;
        s.seedGauge.averageGrownStalkPerBdvPerSeason = averageGrownStalkPerBdvPerSeason;
        emit BeanToMaxLpGpPerBdvRatioChange(
            s.season.current,
            type(uint256).max,
            int80(int128(beanToMaxLpGpPerBdvRatio))
        );

        s.seedGauge.beanToMaxLpGpPerBdvRatio = beanToMaxLpGpPerBdvRatio;
        emit UpdateAverageStalkPerBdvPerSeason(averageGrownStalkPerBdvPerSeason);
        LibCases.setCasesV2();
    }
}
