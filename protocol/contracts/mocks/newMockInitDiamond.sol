/*
 SPDX-License-Identifier: MIT
*/

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import {AppStorage, Storage} from "contracts/beanstalk/AppStorage.sol";
import "contracts/beanstalk/init/InitalizeDiamond.sol";
import {LibWhitelistedTokens} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";
import {LibWhitelist} from "contracts/libraries/Silo/LibWhitelist.sol";
import {LibUnripe} from "contracts/libraries/LibUnripe.sol";
import {BDVFacet} from "contracts/beanstalk/silo/BDVFacet.sol";
import {C} from "contracts/C.sol";


/**
 * @author Publius, Brean
 * @title MockInitDiamond 
 * @notice MockInitDiamond initializes the Beanstalk Diamond.
 * @dev MockInitDiamond additionally: 
 * - Sets the barn raise well. 
 * - Whitelists the bean:wsteth well.
 * - Whitelists unripe assets.
**/
contract MockInitDiamond is InitalizeDiamond {

    // min 1micro stalk earned per season due to germination.
    uint32 constant INIT_UR_BEAN_STALK_EARNED_PER_SEASON = 1;
    uint32 constant INIT_BEAN_WSTETH_WELL_STALK_EARNED_PER_SEASON = 4e6;
    uint128 constant INIT_TOKEN_WURLP_POINTS = 100e18;
    uint32 constant INIT_BEAN_WURLP_PERCENT_TARGET = 50e6;


    function init() external {
        
        // initalize the default state of the diamond.
        // {see. InitalizeDiamond.initalizeDiamond()}
        initalizeDiamond(C.BEAN, C.BEAN_ETH_WELL);
        
        // initalizes unripe assets.
        // sets the underlying LP token of unripeLP to the Bean:wstETH well.
        address underlyingUrLPWell = C.BEAN_WSTETH_WELL;
        whitelistUnderlyingUrLPWell(underlyingUrLPWell);
        initalizeUnripeAssets(underlyingUrLPWell);
    }

    function initalizeUnripeAssets(address well) internal {
        (
            address[] memory unripeTokens, 
            address[] memory underlyingTokens
        ) = getInitalUnripeAndUnderlyingTokens(well);

        // set the underlying unripe tokens.
        setUnderlyingUnripe(
            unripeTokens,
            underlyingTokens,
            underlyingTokens[1]
        );
        // whitelist the unripe assets into the silo.
        whitelistUnripeAssets(
            unripeTokens,
            initalUnripeSiloSettings()
        );
    }

    /**
     * @notice whitelists unripe assets.
     */
    function whitelistUnripeAssets(
        address[] memory tokens,
        Storage.SiloSettings[] memory siloSettings
    ) internal {
        for(uint i; i < tokens.length; i++) {
            // sets the silo settings for each token.
            s.ss[tokens[i]] = siloSettings[i];
            // note: unripeLP is not an LP token (only the underlying is)
            LibWhitelistedTokens.addWhitelistStatus(
                tokens[i],  
                true, // is whitelisted,
                false,
                false
            );
        }
    }

    /**
     * @notice sets the underlying tokens for unripe. 
     * @dev assumes the last unripe token is the unripe LP.
     */
    function setUnderlyingUnripe(
        address[] memory unripeToken,
        address[] memory underlyingToken,
        address barnRaiseWell
    ) internal {
        // sets the underlying unripe for unripe assets.
        for(uint i; i < unripeToken.length; i++) {
            LibUnripe.switchUnderlyingToken(unripeToken[i], underlyingToken[i]);
        }

        // sets the barn raise token to the underlying of the unripe LP.
        s.u[unripeToken[underlyingToken.length - 1]].underlyingToken = barnRaiseWell;
    }

    /**
     * @notice initalizes the unripe silo settings.
     * @dev unripe bean and unrpe lp has the same settings,
     * other than the BDV calculation.
     */
    function initalUnripeSiloSettings() internal view returns (
        Storage.SiloSettings[] memory siloSettings
    ){
        Storage.Implmentation memory impl = Storage.Implmentation({
            target: address(0),
            selector: bytes4(0)
        });
        siloSettings = new Storage.SiloSettings[](2);
        siloSettings[0] = Storage.SiloSettings({
                selector: BDVFacet.unripeBeanToBDV.selector,
                stalkEarnedPerSeason: INIT_UR_BEAN_STALK_EARNED_PER_SEASON,
                stalkIssuedPerBdv: INIT_STALK_ISSUED_PER_BDV,
                milestoneSeason: s.season.current,
                milestoneStem: 0,
                encodeType: 0x00,
                deltaStalkEarnedPerSeason: 0,
                gpSelector: bytes4(0),
                lwSelector: bytes4(0),
                gaugePoints: 0,
                optimalPercentDepositedBdv: 0,
                oracleImplmentation: impl,
                gaugePointImplmentation: impl,
                liquidityWeightImplmentation: impl
            });
        siloSettings[1] = Storage.SiloSettings({
                selector: BDVFacet.unripeLPToBDV.selector,
                stalkEarnedPerSeason: INIT_UR_BEAN_STALK_EARNED_PER_SEASON,
                stalkIssuedPerBdv: INIT_STALK_ISSUED_PER_BDV,
                milestoneSeason: s.season.current,
                milestoneStem: 0,
                encodeType: 0x00,
                deltaStalkEarnedPerSeason: 0,
                gpSelector: bytes4(0),
                lwSelector: bytes4(0),
                gaugePoints: 0,
                optimalPercentDepositedBdv: 0,
                oracleImplmentation: impl,
                gaugePointImplmentation: impl,
                liquidityWeightImplmentation: impl
            });
    }

    /**
     * @notice returns the inital unripe and underlying tokens.
     */
    function getInitalUnripeAndUnderlyingTokens(address underlyingUrLPWell) internal pure returns (
        address[] memory unripeTokens,
        address[] memory underlyingTokens
    ) {
        unripeTokens = new address[](2);
        underlyingTokens = new address[](2);
        unripeTokens[0] = C.UNRIPE_BEAN;
        unripeTokens[1] = C.UNRIPE_LP;
        underlyingTokens[0] = C.BEAN;
        underlyingTokens[1] = underlyingUrLPWell; 
    }

    /**
     * @notice if unripe assets are being whitelisted, the underlying
     * well must be whitelisted.
     */
    function whitelistUnderlyingUrLPWell(address well) internal {
        // whitelist bean:stETH well
        Storage.Implmentation memory impl = Storage.Implmentation({
            target: address(0),
            selector: bytes4(0)
        });
        // note: no error checking:
        s.ss[well] = Storage.SiloSettings({
            selector: BDVFacet.wellBdv.selector,
            stalkEarnedPerSeason: INIT_BEAN_WSTETH_WELL_STALK_EARNED_PER_SEASON,
            stalkIssuedPerBdv: INIT_STALK_ISSUED_PER_BDV,
            milestoneSeason: s.season.current,
            milestoneStem: 0,
            encodeType: 0x01,
            deltaStalkEarnedPerSeason: 0,
            gpSelector: IGaugePointFacet.defaultGaugePointFunction.selector,
            lwSelector: ILiquidityWeightFacet.maxWeight.selector,
            gaugePoints: INIT_TOKEN_WURLP_POINTS,
            optimalPercentDepositedBdv: INIT_BEAN_WURLP_PERCENT_TARGET,
            oracleImplmentation: impl,
            gaugePointImplmentation: impl,
            liquidityWeightImplmentation: Storage.Implmentation(address(0), bytes4(ILiquidityWeightFacet.maxWeight.selector))
        });

        // updates the optimal percent deposited for bean:eth.
        LibWhitelist.updateOptimalPercentDepositedBdvForToken(
            C.BEAN_ETH_WELL,
            INIT_BEAN_TOKEN_WELL_PERCENT_TARGET - INIT_BEAN_WURLP_PERCENT_TARGET
        );

        // update whitelist status.
        LibWhitelistedTokens.addWhitelistStatus(
                well,
                true, // is whitelisted,
                true, // is LP
                true  // is well 
            );

        s.twaReserves[well].reserve0 = 1;
        s.twaReserves[well].reserve1 = 1;
    }
}