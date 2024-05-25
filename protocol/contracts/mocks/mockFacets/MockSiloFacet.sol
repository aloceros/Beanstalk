/*
 SPDX-License-Identifier: MIT
*/

pragma solidity ^0.8.20;

import "contracts/libraries/LibRedundantMath256.sol";
import "../../beanstalk/silo/SiloFacet/SiloFacet.sol";
import "../../libraries/Silo/LibWhitelist.sol";
import "../../libraries/Silo/LibWhitelistedTokens.sol";
import "../../libraries/Well/LibWell.sol";
import "../../libraries/LibTractor.sol";

/**
 * @author Publius
 * @title Mock Silo Facet
 **/

contract MockSiloFacet is SiloFacet {
    uint256 private constant AMOUNT_TO_BDV_BEAN_ETH = 119894802186829;
    uint256 private constant AMOUNT_TO_BDV_BEAN_3CRV = 992035;
    uint256 private constant AMOUNT_TO_BDV_BEAN_LUSD = 983108;

    using SafeCast for uint256;
    using LibRedundantMath128 for uint128;
    using LibRedundantMath256 for uint256;

    /**
     * @notice emitted when the farmers germinating stalk changes.
     */
    event FarmerGerminatingStalkBalanceChanged(address indexed account, int256 delta);

    /**
     * @notice emitted when the total germinating amount/bdv changes.
     */
    event TotalGerminatingBalanceChanged(
        uint256 season,
        address indexed token,
        int256 delta,
        int256 deltaBdv
    );

    function mockBDV(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function mockBDVIncrease(uint256 amount) external pure returns (uint256) {
        return amount.mul(3).div(2);
    }

    // function mockUnripeLPDeposit(uint256 t, uint32 _s, uint256 amount, uint256 bdv) external {
    //     _mowLegacy(LibTractor._user());

    //     uint256 unripeLP = getUnripeForAmount(t, amount);
    //     bdv = bdv.mul(C.initialRecap()).div(1e18);
    //     incrementTotalDepositedAmount(C.UNRIPE_LP, unripeLP);

    //     // from the seed gauge on, mowAndMigrate does not increment BDV. instead, the init script has a one-time
    //     // bdv increment of all unripe assets. Thus, we increment total deposited here for testing purposes.
    //     incrementTotalDepositedBDV(C.UNRIPE_LP, bdv);

    //     uint256 seeds = bdv.mul(LibTokenSilo.getLegacySeedsPerToken(C.UNRIPE_LP));
    //     uint256 stalk = bdv.mul(s.system.silo.assetSettings[C.UNRIPE_LP].stalkIssuedPerBdv).add(
    //         stalkRewardLegacy(seeds, s.system.season.current - _s)
    //     );
    //     // not germinating because this is a old deposit.
    //     LibSilo.mintActiveStalk(LibTractor._user(), stalk);
    //     mintSeeds(LibTractor._user(), seeds);
    //     LibTransfer.receiveToken(
    //         IERC20(C.UNRIPE_LP),
    //         unripeLP,
    //         LibTractor._user(),
    //         LibTransfer.From.EXTERNAL
    //     );
    // }

    // function mockUnripeBeanDeposit(uint32 _s, uint256 amount) external {
    //     _mowLegacy(LibTractor._user());
    //     uint256 partialAmount = amount.mul(C.initialRecap()).div(1e18);
    //     incrementTotalDepositedAmount(C.UNRIPE_BEAN, amount);

    //     // from the seed gauge on, mowAndMigrate does not increment BDV. instead, the init script has a one-time
    //     // bdv increment of all unripe assets. Thus, we increment total deposited here for testing purposes.
    //     incrementTotalDepositedBDV(C.UNRIPE_BEAN, partialAmount);

    //     uint256 seeds = partialAmount.mul(LibTokenSilo.getLegacySeedsPerToken(C.UNRIPE_BEAN));
    //     uint256 stalk = partialAmount
    //         .mul(s.system.silo.assetSettings[C.UNRIPE_BEAN].stalkIssuedPerBdv)
    //         .add(stalkRewardLegacy(seeds, s.system.season.current - _s));

    //     LibSilo.mintActiveStalk(LibTractor._user(), stalk);
    //     mintSeeds(LibTractor._user(), seeds);
    //     LibTransfer.receiveToken(
    //         IERC20(C.UNRIPE_BEAN),
    //         amount,
    //         LibTractor._user(),
    //         LibTransfer.From.EXTERNAL
    //     );
    // }

    // modifier mowSenderLegacy() {
    //     _mowLegacy(LibTractor._user());
    //     _;
    // }

    /**
     * @dev Claims the Grown Stalk for `account` and applies it to their Stalk
     * balance.
     *
     * A Farmer cannot receive Seeds unless the Farmer's `lastUpdate` Season is
     * equal to the current Season. Otherwise, they would receive extra Grown
     * Stalk when they receive Seeds.
     *
     * This is why `_mow()` must be called before any actions that change Seeds,
     * including:
     *  - {SiloFacet-deposit}
     *  - {SiloFacet-withdrawDeposit}
     *  - {SiloFacet-withdrawDeposits}
     *  - {_plant}
     *  - {SiloFacet-transferDeposit(s)}
     */
    // function _mowLegacy(address account) internal {
    //     uint32 _lastUpdate = s.accounts[account].lastUpdate;

    //     // If `account` was already updated this Season, there's no Stalk to Mow.
    //     // _lastUpdate > s.system.season.current should not be possible, but it is checked anyway.
    //     if (_lastUpdate >= s.system.season.current) return;

    //     // Increments `plenty` for `account` if a Flood has occured.
    //     // Saves Rain Roots for `account` if it is Raining.
    //     handleRainAndSopsLegacy(account, _lastUpdate);

    //     // Calculate the amount of Grown Stalk claimable by `account`.
    //     // Increase the account's balance of Stalk and Roots.
    //     __mowLegacy(account);

    //     // Reset timer so that Grown Stalk for a particular Season can only be
    //     // claimed one time.
    //     s.accounts[account].lastUpdate = s.system.season.current;
    // }

    // function __mowLegacy(address account) private {
    //     // If this `account` has no Seeds, skip to save gas.
    //     if (s.accounts[account].silo.seeds == 0) return;
    //     LibSilo.mintActiveStalk(
    //         account,
    //         s.accounts[account].silo.seeds * (s.system.season.current - s.accounts[account].lastUpdate)
    //     );
    // }

    function handleRainAndSopsLegacy(address account, uint32 _lastUpdate) private {
        // If no roots, reset Sop counters variables
        if (s.accounts[account].roots == 0) {
            s.accounts[account].lastSop = s.system.season.rainStart;
            s.accounts[account].lastRain = 0;
            return;
        }
        // If a Sop has occured since last update, calculate rewards and set last Sop.
        if (s.system.season.lastSopSeason > _lastUpdate) {
            s.accounts[account].sop.plenty = LibSilo.balanceOfPlenty(account);
            s.accounts[account].lastSop = s.system.season.lastSop;
        }
        if (s.system.season.raining) {
            // If rain started after update, set account variables to track rain.
            if (s.system.season.rainStart > _lastUpdate) {
                s.accounts[account].lastRain = s.system.season.rainStart;
                s.accounts[account].sop.roots = s.accounts[account].roots;
            }
            // If there has been a Sop since rain started,
            // save plentyPerRoot in case another SOP happens during rain.
            if (s.system.season.lastSop == s.system.season.rainStart)
                s.accounts[account].sop.plentyPerRoot = s.system.sops[s.system.season.lastSop];
        } else if (s.accounts[account].lastRain > 0) {
            // Reset Last Rain if not raining.
            s.accounts[account].lastRain = 0;
        }
    }

    //mock adding seeds to account for legacy tests
    // function mintSeeds(address account, uint256 seeds) internal {
    //     AppStorage storage s = LibAppStorage.diamondStorage();

    //     // Increase supply of Seeds; Add Seeds to the balance of `account`
    //     s.accounts[account].silo.seeds = s.accounts[account].silo.seeds.add(seeds);

    //     // emit SeedsBalanceChanged(account, int256(seeds)); //don't really care about the event for unit testing purposes of unripe stuff
    // }

    function getUnripeForAmount(uint256 t, uint256 amount) private pure returns (uint256) {
        if (t == 0) return amount.mul(AMOUNT_TO_BDV_BEAN_ETH).div(1e18);
        else if (t == 1) return amount.mul(AMOUNT_TO_BDV_BEAN_3CRV).div(1e18);
        else return amount.mul(AMOUNT_TO_BDV_BEAN_LUSD).div(1e18);
    }

    //////////////////////// ADD DEPOSIT ////////////////////////

    // function balanceOfSeeds(address account) public view returns (uint256) {
    //     return s.accounts[account].silo.seeds;
    // }

    /**
     * @notice Whitelists a token for testing purposes.
     * @dev no gauge. no error checking.
     */
    function mockWhitelistToken(
        address token,
        bytes4 selector,
        uint16 stalkIssuedPerBdv,
        uint24 stalkEarnedPerSeason
    ) external {
        s.system.silo.assetSettings[token].selector = selector;
        s.system.silo.assetSettings[token].stalkIssuedPerBdv = stalkIssuedPerBdv; //previously just called "stalk"
        s.system.silo.assetSettings[token].stalkEarnedPerSeason = stalkEarnedPerSeason; //previously called "seeds"

        s.system.silo.assetSettings[token].milestoneSeason = uint24(s.system.season.current);
        LibWhitelistedTokens.addWhitelistStatus(
            token,
            true,
            true,
            selector == LibWell.WELL_BDV_SELECTOR
        );

        // emit WhitelistToken(token, selector, stalkEarnedPerSeason, stalkIssuedPerBdv);
    }

    /**
     * @dev Whitelists a token for testing purposes.
     * @dev no error checking.
     */
    function mockWhitelistTokenWithGauge(
        address token,
        bytes4 selector,
        uint16 stalkIssuedPerBdv,
        uint24 stalkEarnedPerSeason,
        bytes1 encodeType,
        bytes4 gaugePointSelector,
        bytes4 liquidityWeightSelector,
        uint128 gaugePoints,
        uint64 optimalPercentDepositedBdv
    ) external {
        if (stalkEarnedPerSeason == 0) stalkEarnedPerSeason = 1;
        s.system.silo.assetSettings[token].selector = selector;
        s.system.silo.assetSettings[token].stalkEarnedPerSeason = stalkEarnedPerSeason;
        s.system.silo.assetSettings[token].stalkIssuedPerBdv = stalkIssuedPerBdv;
        s.system.silo.assetSettings[token].milestoneSeason = uint32(s.system.season.current);
        s.system.silo.assetSettings[token].encodeType = encodeType;
        s.system.silo.assetSettings[token].gpSelector = gaugePointSelector;
        s.system.silo.assetSettings[token].lwSelector = liquidityWeightSelector;
        s.system.silo.assetSettings[token].gaugePoints = gaugePoints;
        s.system.silo.assetSettings[token].optimalPercentDepositedBdv = optimalPercentDepositedBdv;

        LibWhitelistedTokens.addWhitelistStatus(
            token,
            true,
            true,
            selector == LibWell.WELL_BDV_SELECTOR
        );
    }

    function addWhitelistSelector(address token, bytes4 selector) external {
        s.system.silo.assetSettings[token].selector = selector;
    }

    function removeWhitelistSelector(address token) external {
        s.system.silo.assetSettings[token].selector = 0x00000000;
    }

    function mockLiquidityWeight() external pure returns (uint256) {
        return 0.5e18;
    }

    function mockUpdateLiquidityWeight(address token, bytes4 selector) external {
        s.system.silo.assetSettings[token].lwSelector = selector;
    }

    function incrementTotalDepositedAmount(address token, uint256 amount) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.system.silo.balances[token].deposited = s.system.silo.balances[token].deposited.add(
            amount.toUint128()
        );
    }

    function incrementTotalDepositedBDV(address token, uint256 amount) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.system.silo.balances[token].depositedBdv = s.system.silo.balances[token].depositedBdv.add(
            amount.toUint128()
        );
    }

    /**
     * @notice mock functionality that allows the deposit at any stem and bdv
     * @dev does not support germinating stems.
     * used in enroot tests.
     */
    function depositAtStemAndBdv(
        address token,
        uint256 _amount,
        int96 stem,
        uint128 bdv,
        LibTransfer.From mode
    ) external {
        LibTransfer.receiveToken(IERC20(token), _amount, LibTractor._user(), mode);
        _depositAtStemAndBdv(LibTractor._user(), token, _amount, stem, bdv);
    }

    /**
     * @notice internal logic for depositing. See Deposit flow.
     */
    function _depositAtStemAndBdv(
        address account,
        address token,
        uint256 amount,
        int96 stem,
        uint128 bdv
    ) internal {
        LibTokenSilo.incrementTotalDeposited(token, amount, bdv);
        LibTokenSilo.addDepositToAccount(
            account,
            token,
            stem,
            amount,
            bdv,
            LibTokenSilo.Transfer.emitTransferSingle
        );
        uint256 stalk = bdv.mul(s.system.silo.assetSettings[token].stalkIssuedPerBdv);
        LibSilo.mintActiveStalk(account, uint128(stalk));
    }

    function setStalkAndRoots(address account, uint128 stalk, uint256 roots) external {
        s.system.silo.stalk = stalk;
        s.system.silo.roots = stalk;
        s.accounts[account].silo.stalk = stalk;
        s.accounts[account].roots = roots;
    }
}
