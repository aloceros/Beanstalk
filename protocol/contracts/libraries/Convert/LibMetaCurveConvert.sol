// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {LibRedundantMath256} from "contracts/libraries/LibRedundantMath256.sol";
import {LibConvertData} from "./LibConvertData.sol";
import {LibBeanMetaCurve} from "../Curve/LibBeanMetaCurve.sol";
import {LibCurve} from "../Curve/LibCurve.sol";
import {LibAppStorage} from "../LibAppStorage.sol";
import {C} from "contracts/C.sol";

/**
 * @title LibMetaCurveConvert
 * @author Publius
 */
library LibMetaCurveConvert {
    using LibRedundantMath256 for uint256;
    using LibConvertData for bytes;

    uint256 private constant N_COINS = 2;
    uint256 private constant FEED2 = 2000000;
    uint256 private constant ADMIN_FEE = 5e9;
    uint256 private constant FEE_DENOMINATOR = 1e10;

    /**
     * @notice Calculate the amount of BEAN that would exist in a Curve metapool
     * if it were "at peg", i.e. if there was 1 BEAN per 1 USD of 3CRV.
     * @dev Assumes that `balances[1]` is 3CRV.
     */
    function beansAtPeg(uint256[2] memory balances) internal view returns (uint256 beans) {
        return balances[1].mul(C.curve3Pool().get_virtual_price()).div(1e30);
    }

    function lpToPeg(uint256[2] memory balances, uint256 atPeg) internal view returns (uint256 lp) {
        uint256 a = C.curveMetapool().A_precise();
        uint256[2] memory xp = LibBeanMetaCurve.getXP(balances);
        uint256 d0 = LibCurve.getD(xp, a);
        uint256 toPeg = balances[0].sub(atPeg);
        toPeg = _toPegWithFee(toPeg, balances, d0, a);
        lp = _calcLPTokenAmount(toPeg, balances, d0, a);
    }

    //////////////////// INTERNAL ////////////////////

    function _calcLPTokenAmount(
        uint256 amount,
        uint256[2] memory balances,
        uint256 D0,
        uint256 a
    ) internal view returns (uint256) {
        balances[0] = balances[0].sub(amount);
        uint256[2] memory xp = LibBeanMetaCurve.getXP(balances);
        uint256 D1 = LibCurve.getD(xp, a);
        uint256 diff = D0.sub(D1);
        return diff.mul(C.curveMetapool().totalSupply()).div(D0);
    }

    function _toPegWithFee(
        uint256 amount,
        uint256[2] memory balances,
        uint256 D0,
        uint256 a
    ) internal view returns (uint256) {
        uint256[2] memory xp = LibBeanMetaCurve.getXP(balances);
        uint256 new_y = LibBeanMetaCurve.getXP0(balances[0].sub(amount));
        uint256 D1 = LibCurve.getD([new_y, xp[1]], a);

        uint256[N_COINS] memory xp_reduced;
        uint256 dx_expected = xp[0].mul(D1).div(D0).sub(new_y);
        xp_reduced[0] = xp[0].sub(FEED2.mul(dx_expected) / FEE_DENOMINATOR);

        dx_expected = xp[1].sub(xp[1].mul(D1).div(D0));
        xp_reduced[1] = xp[1].sub(FEED2.mul(dx_expected) / FEE_DENOMINATOR);

        uint256 yd = LibCurve.getYD(a, 0, xp_reduced, D1);
        uint256 dy = xp_reduced[0].sub(yd);
        dy = LibBeanMetaCurve.getX0(dy.sub(1));
        uint256 dy_0 = LibBeanMetaCurve.getX0(xp[0].sub(new_y));

        return dy_0.add(dy_0.sub(dy).mul(ADMIN_FEE).div(FEE_DENOMINATOR));
    }
}
