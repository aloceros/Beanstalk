/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.20;

import {C} from "contracts/C.sol";
import {LibRedundantMath32} from "contracts/libraries/LibRedundantMath32.sol";
import {LibRedundantMath128} from "contracts/libraries/LibRedundantMath128.sol";
import {LibRedundantMath256} from "contracts/libraries/LibRedundantMath256.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {LibTractor} from "contracts/libraries/LibTractor.sol";
import {LibTransfer} from "contracts/libraries/Token/LibTransfer.sol";
import {LibDibbler} from "contracts/libraries/LibDibbler.sol";
import {ReentrancyGuard} from "../ReentrancyGuard.sol";
import {Invariable} from "contracts/beanstalk/Invariable.sol";
import {Listing} from "contracts/beanstalk/market/MarketplaceFacet/Listing.sol";

/**
 * @title FieldFacet
 * @author Publius, Brean
 * @notice The Field is where Beans are Sown and Pods are Harvested.
 */
contract FieldFacet is Invariable, Listing {
    using LibRedundantMath256 for uint256;
    using LibRedundantMath32 for uint32;
    using LibRedundantMath128 for uint128;

    /**
     * @notice Emitted from {LibDibbler.sow} when an `account` creates a plot.
     * A Plot is a set of Pods created in from a single {sow} or {fund} call.
     * @param account The account that sowed Beans for Pods
     * @param index The place in line of the Plot
     * @param beans The amount of Beans burnt to create the Plot
     * @param pods The amount of Pods assocated with the created Plot
     */
    event Sow(address indexed account, uint256 index, uint256 beans, uint256 pods);

    /**
     * @notice Emitted when `account` claims the Beans associated with Harvestable Pods.
     * @param account The account that owns the `plots`
     * @param plots The indices of Plots that were harvested
     * @param beans The amount of Beans transferred to `account`
     */
    event Harvest(address indexed account, uint256[] plots, uint256 beans);

    //////////////////// SOW ////////////////////

    /**
     * @notice Sow Beans in exchange for Pods.
     * @param beans The number of Beans to Sow
     * @param minTemperature The minimum Temperature at which to Sow
     * @param mode The balance to transfer Beans from; see {LibTransfer.From}
     * @return pods The number of Pods received
     * @dev
     *
     * `minTemperature` has precision of 1e6. Wraps {sowWithMin} with `minSoil = beans`.
     *
     * NOTE: previously minTemperature was measured to 1e2 (1% = 1)
     *
     * Rationale for {sow} accepting a `minTemperature` parameter:
     * If someone sends a Sow transaction at the end of a Season, it could be
     * executed early in the following Season, at which time the temperature may be
     * significantly lower due to Morning Auction functionality.
     */
    function sow(
        uint256 beans,
        uint256 minTemperature,
        LibTransfer.From mode
    ) external payable fundsSafu noSupplyIncrease oneOutFlow(C.BEAN) returns (uint256 pods) {
        pods = sowWithMin(beans, minTemperature, beans, mode);
    }

    /**
     * @notice Sow Beans in exchange for Pods. Use at least `minSoil`.
     * @param beans The number of Beans to Sow
     * @param minTemperature The minimum Temperature at which to Sow
     * @param minSoil The minimum amount of Soil to use; reverts if there is
     * less than this much Soil available upon execution
     * @param mode The balance to transfer Beans from; see {LibTrasfer.From}
     * @return pods The number of Pods received
     */
    function sowWithMin(
        uint256 beans,
        uint256 minTemperature,
        uint256 minSoil,
        LibTransfer.From mode
    ) public payable fundsSafu noSupplyIncrease oneOutFlow(C.BEAN) returns (uint256 pods) {
        // `soil` is the remaining Soil
        (uint256 soil, uint256 _morningTemperature, bool abovePeg) = _totalSoilAndTemperature();

        require(soil >= minSoil && beans >= minSoil, "Field: Soil Slippage");
        require(_morningTemperature >= minTemperature, "Field: Temperature Slippage");

        // If beans >= soil, Sow all of the remaining Soil
        if (beans < soil) {
            soil = beans;
        }

        // 1 Bean is Sown in 1 Soil, i.e. soil = beans
        pods = _sow(soil, _morningTemperature, abovePeg, mode);
    }

    /**
     * @dev Burn Beans, Sows at the provided `_morningTemperature`, increments the total
     * number of `beanSown`.
     */
    function _sow(
        uint256 beans,
        uint256 _morningTemperature,
        bool peg,
        LibTransfer.From mode
    ) internal returns (uint256 pods) {
        beans = LibTransfer.burnToken(C.bean(), beans, LibTractor._user(), mode);
        pods = LibDibbler.sow(beans, _morningTemperature, LibTractor._user(), peg);
        s.beanSown += SafeCast.toUint128(beans);
    }

    //////////////////// HARVEST ////////////////////

    /**
     * @notice Harvest Pods from the Field.
     * @param fieldIndex The index of the Field to Harvest from.
     * @param plots List of plot IDs to Harvest
     * @param mode The balance to transfer Beans to; see {LibTrasfer.To}
     * @dev Redeems Pods for Beans. When Pods become Harvestable, they are
     * redeemable for 1 Bean each.
     *
     * The Beans used to pay Harvestable Pods are minted during {Sun.stepSun}.
     * Beanstalk holds these Beans until `harvest()` is called.
     *
     * Pods are "burned" when the corresponding Plot is deleted from
     * `s.accounts[account].fields[fieldIndex].plots`.
     */
    function harvest(
        uint256 fieldIndex,
        uint256[] calldata plots,
        LibTransfer.To mode
    ) external payable fundsSafu noSupplyChange oneOutFlow(C.BEAN) {
        uint256 beansHarvested = _harvest(fieldIndex, plots);
        LibTransfer.sendToken(C.bean(), beansHarvested, LibTractor._user(), mode);
    }

    /**
     * @dev Ensure that each Plot is at least partially harvestable, burn the Plot,
     * update the total harvested, and emit a {Harvest} event.
     */
    function _harvest(
        uint256 fieldIndex,
        uint256[] calldata plots
    ) internal returns (uint256 beansHarvested) {
        for (uint256 i; i < plots.length; ++i) {
            // The Plot is partially harvestable if its index is less than
            // the current harvestable index.
            require(plots[i] < s.fields[fieldIndex].harvestable, "Field: Plot not Harvestable");
            uint256 harvested = _harvestPlot(LibTractor._user(), fieldIndex, plots[i]);
            beansHarvested += harvested;
        }
        s.fields[fieldIndex].harvested += beansHarvested;
        emit Harvest(LibTractor._user(), plots, beansHarvested);
    }

    /**
     * @dev Check if a Plot is at least partially Harvestable; calculate how many
     * Pods are Harvestable, create a new Plot if necessary.
     */
    function _harvestPlot(
        address account,
        uint256 fieldIndex,
        uint256 index
    ) private returns (uint256 harvestablePods) {
        // Check that `account` holds this Plot.
        uint256 pods = s.accounts[account].fields[fieldIndex].plots[index];
        require(pods > 0, "Field: no plot");

        // Calculate how many Pods are harvestable.
        // The upstream _harvest function checks that at least some Pods
        // are harvestable.
        harvestablePods = s.fields[fieldIndex].harvestable.sub(index);
        _cancelPodListing(LibTractor._user(), fieldIndex, index);
        delete s.accounts[account].fields[fieldIndex].plots[index];

        // If the entire Plot was harvested, exit.
        if (harvestablePods >= pods) {
            return pods;
        }

        // Create a new Plot with remaining Pods.
        s.accounts[account].fields[fieldIndex].plots[index.add(harvestablePods)] = pods.sub(
            harvestablePods
        );
    }

    //////////////////// GETTERS ////////////////////

    /**
     * @notice Returns the total number of Pods ever minted in the Field.
     * @param fieldIndex The index of the Field to query.
     */
    function podIndex(uint256 fieldIndex) public view returns (uint256) {
        return s.fields[fieldIndex].pods;
    }

    /**
     * @notice Returns the index below which Pods are Harvestable.
     * @param fieldIndex The index of the Field to query.
     */
    function harvestableIndex(uint256 fieldIndex) public view returns (uint256) {
        return s.fields[fieldIndex].harvestable;
    }

    /**
     * @notice Returns the number of outstanding Pods. Includes Pods that are
     * currently Harvestable but have not yet been Harvested.
     * @param fieldIndex The index of the Field to query.
     */
    function totalPods(uint256 fieldIndex) public view returns (uint256) {
        return s.fields[fieldIndex].pods - s.fields[fieldIndex].harvested;
    }

    /**
     * @notice Returns the number of Pods that have ever been Harvested.
     * @param fieldIndex The index of the Field to query.
     */
    function totalHarvested(uint256 fieldIndex) public view returns (uint256) {
        return s.fields[fieldIndex].harvested;
    }

    /**
     * @notice Returns the number of Pods that are currently Harvestable but
     * have not yet been Harvested.
     * @dev This is the number of Pods that Beanstalk is prepared to pay back,
     * but that haven’t yet been claimed via the `harvest()` function.
     * @param fieldIndex The index of the Field to query.
     */
    function totalHarvestable(uint256 fieldIndex) public view returns (uint256) {
        return s.fields[fieldIndex].harvestable - s.fields[fieldIndex].harvested;
    }

    /**
     * @notice Returns the number of Pods that are not yet Harvestable. Also known as the Pod Line.
     * @param fieldIndex The index of the Field to query.
     */
    function totalUnharvestable(uint256 fieldIndex) public view returns (uint256) {
        return s.fields[fieldIndex].pods - s.fields[fieldIndex].harvestable;
    }

    /**
     * @notice Returns the number of Pods remaining in a Plot.
     * @dev Plots are only stored in the `s.accounts[account].fields[fieldIndex].plots` mapping.
     * @param fieldIndex The index of the Field to query.
     */
    function plot(
        address account,
        uint256 fieldIndex,
        uint256 index
    ) public view returns (uint256) {
        return s.accounts[account].fields[fieldIndex].plots[index];
    }

    /**
     * @dev Gets the current `soil`, `_morningTemperature` and `abovePeg`. Provided as a gas
     * optimization to prevent recalculation of {LibDibbler.morningTemperature} for
     * upstream functions.
     * Note: the `soil` return value is symmetric with `totalSoil`.
     */
    function _totalSoilAndTemperature()
        private
        view
        returns (uint256 soil, uint256 _morningTemperature, bool abovePeg)
    {
        _morningTemperature = LibDibbler.morningTemperature();
        abovePeg = s.season.abovePeg;

        // Below peg: Soil is fixed to the amount set during {calcCaseId}.
        // Morning Temperature is dynamic, starting small and logarithmically
        // increasing to `s.weather.t` across the first 25 blocks of the Season.
        if (!abovePeg) {
            soil = uint256(s.soil);
        }
        // Above peg: the maximum amount of Pods that Beanstalk is willing to mint
        // stays fixed; since {morningTemperature} is scaled down when `delta < 25`, we
        // need to scale up the amount of Soil to hold Pods constant.
        else {
            soil = LibDibbler.scaleSoilUp(
                uint256(s.soil), // max soil offered this Season, reached when `t >= 25`
                uint256(s.weather.t).mul(LibDibbler.TEMPERATURE_PRECISION), // max temperature
                _morningTemperature // temperature adjusted by number of blocks since Sunrise
            );
        }
    }

    //////////////////// GETTERS: SOIL ////////////////////

    /**
     * @notice Returns the total amount of available Soil. 1 Bean can be Sown in
     * 1 Soil for Pods.
     * @dev When above peg, Soil is dynamic because the number of Pods that
     * Beanstalk is willing to mint is fixed.
     */
    function totalSoil() external view returns (uint256) {
        // Below peg: Soil is fixed to the amount set during {calcCaseId}.
        if (!s.season.abovePeg) {
            return uint256(s.soil);
        }

        // Above peg: Soil is dynamic
        return
            LibDibbler.scaleSoilUp(
                uint256(s.soil), // min soil
                uint256(s.weather.t).mul(LibDibbler.TEMPERATURE_PRECISION), // max temperature
                LibDibbler.morningTemperature() // temperature adjusted by number of blocks since Sunrise
            );
    }

    //////////////////// GETTERS: TEMPERATURE ////////////////////

    /**
     * @notice Returns the current Temperature, the interest rate offered by Beanstalk.
     * The Temperature scales up during the first 25 blocks after Sunrise.
     */
    function temperature() external view returns (uint256) {
        return LibDibbler.morningTemperature();
    }

    /**
     * @notice Returns the max Temperature that Beanstalk is willing to offer this Season.
     * @dev For gas efficiency, Beanstalk stores `s.weather.t` as a uint32 with precision of 1e2.
     * Here we convert to uint256 and scale up by TEMPERATURE_PRECISION to match the
     * precision needed for the Morning Auction functionality.
     */
    function maxTemperature() external view returns (uint256) {
        return uint256(s.weather.t).mul(LibDibbler.TEMPERATURE_PRECISION);
    }

    //////////////////// GETTERS: PODS ////////////////////

    /**
     * @notice Returns the remaining Pods that could be issued this Season.
     */
    function remainingPods() external view returns (uint256) {
        return uint256(LibDibbler.remainingPods());
    }
}
