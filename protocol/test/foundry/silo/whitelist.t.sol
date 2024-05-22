// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import {TestHelper, LibTransfer, C} from "test/foundry/utils/TestHelper.sol";
import {IMockFBeanstalk} from "contracts/interfaces/IMockFBeanstalk.sol";
import {MockToken} from "contracts/mocks/MockToken.sol";

/**
 * @notice Tests the functionality of whitelisting.
 */
contract WhitelistTest is TestHelper {
    // events
    event AddWhitelistStatus(
        address token,
        uint256 index,
        bool isWhitelisted,
        bool isWhitelistedLp,
        bool isWhitelistedWell
    );
    event WhitelistToken(
        address indexed token,
        bytes4 selector,
        uint32 stalkEarnedPerSeason,
        uint256 stalkIssuedPerBdv,
        bytes4 gpSelector,
        bytes4 lwSelector,
        uint128 gaugePoints,
        uint64 optimalPercentDepositedBdv
    );

    function setUp() public {
        initializeBeanstalkTestState(true, false);
    }

    // reverts if not owner.
    function test_whitelistRevertOwner(uint i) public {
        vm.prank(address(bytes20(keccak256(abi.encode(i)))));
        vm.expectRevert("LibDiamond: Must be contract or owner");
        bs.whitelistToken(address(0), bytes4(0), 0, 0, bytes4(0), bytes4(0), 0, 0);

        vm.expectRevert("LibDiamond: Must be contract or owner");
        bs.whitelistTokenWithEncodeType(
            address(0),
            bytes4(0),
            0,
            0,
            bytes1(0),
            bytes4(0),
            bytes4(0),
            0,
            0
        );
    }

    // reverts with invalid BDV selector.
    function test_whitelistRevertInvalidBDVSelector(uint i) public prank(BEANSTALK) {
        bytes4 bdvSelector = bytes4(keccak256(abi.encode(i)));

        vm.expectRevert("Whitelist: Invalid BDV selector");
        bs.whitelistToken(address(0), bdvSelector, 0, 0, bytes4(0), bytes4(0), 0, 0);

        vm.expectRevert("Whitelist: Invalid BDV selector");
        bs.whitelistTokenWithEncodeType(
            address(0),
            bdvSelector,
            0,
            0,
            bytes1(0x01),
            bytes4(0),
            bytes4(0),
            0,
            0
        );
    }

    function test_whitelistRevertInvalidGaugePointSelector(uint i) public prank(BEANSTALK) {
        bytes4 bdvSelector = IMockFBeanstalk.beanToBDV.selector;
        bytes4 gaugePointSelector = bytes4(keccak256(abi.encode(i)));

        vm.expectRevert("Whitelist: Invalid GaugePoint selector");
        bs.whitelistToken(address(0), bdvSelector, 0, 0, gaugePointSelector, bytes4(0), 0, 0);

        vm.expectRevert("Whitelist: Invalid GaugePoint selector");
        bs.whitelistTokenWithEncodeType(
            address(0),
            bdvSelector,
            0,
            0,
            bytes1(0),
            gaugePointSelector,
            bytes4(0),
            0,
            0
        );
    }

    function test_whitelistRevertInvalidLiquidityWeightSelector(uint i) public prank(BEANSTALK) {
        bytes4 bdvSelector = IMockFBeanstalk.beanToBDV.selector;
        bytes4 gaugePointSelector = IMockFBeanstalk.defaultGaugePointFunction.selector;
        bytes4 liquidityWeightSelector = bytes4(keccak256(abi.encode(i)));

        vm.expectRevert("Whitelist: Invalid LiquidityWeight selector");
        bs.whitelistToken(
            address(0),
            bdvSelector,
            0,
            0,
            gaugePointSelector,
            liquidityWeightSelector,
            0,
            0
        );

        vm.expectRevert("Whitelist: Invalid LiquidityWeight selector");
        bs.whitelistTokenWithEncodeType(
            address(0),
            bdvSelector,
            0,
            0,
            bytes1(0),
            gaugePointSelector,
            liquidityWeightSelector,
            0,
            0
        );
    }

    function test_whitelistRevertExistingWhitelistedToken() public prank(BEANSTALK) {
        bytes4 bdvSelector = IMockFBeanstalk.beanToBDV.selector;
        bytes4 gaugePointSelector = IMockFBeanstalk.defaultGaugePointFunction.selector;
        bytes4 liquidityWeightSelector = IMockFBeanstalk.maxWeight.selector;
        address token = address(C.bean());

        vm.expectRevert("Whitelist: Token already whitelisted");
        bs.whitelistToken(
            token,
            bdvSelector,
            0,
            0,
            gaugePointSelector,
            liquidityWeightSelector,
            0,
            0
        );

        vm.expectRevert("Whitelist: Token already whitelisted");
        bs.whitelistTokenWithEncodeType(
            token,
            bdvSelector,
            0,
            0,
            bytes1(0),
            gaugePointSelector,
            liquidityWeightSelector,
            0,
            0
        );
    }

    //// WHITELIST ////
    // Theorically, a number of tokens that may be used within the beanstalk system can be whitelisted.
    // However, this is not enforced on the contract level and thus is not tested here.
    // For example, the contract assumes further silo whitelisted assets will be an LP token.

    /**
     * @notice validates general whitelist functionality.
     */
    function test_whitelistToken(
        uint32 stalkEarnedPerSeason,
        uint32 stalkIssuedPerBdv,
        uint128 gaugePoints,
        uint64 optimalPercentDepositedBdv
    ) public prank(BEANSTALK) {
        address token = address(new MockToken("Mock Token", "MTK"));
        bytes4 bdvSelector = IMockFBeanstalk.beanToBDV.selector;
        bytes4 gaugePointSelector = IMockFBeanstalk.defaultGaugePointFunction.selector;
        bytes4 liquidityWeightSelector = IMockFBeanstalk.maxWeight.selector;

        vm.expectEmit();
        emit AddWhitelistStatus(token, 5, true, true, false);
        vm.expectEmit();
        emit WhitelistToken(
            token,
            bdvSelector,
            stalkEarnedPerSeason == 0 ? 1 : stalkEarnedPerSeason,
            stalkIssuedPerBdv,
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );
        bs.whitelistToken(
            token,
            bdvSelector,
            stalkIssuedPerBdv,
            stalkEarnedPerSeason,
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );

        verifyWhitelistState(
            token,
            bdvSelector,
            stalkEarnedPerSeason,
            stalkIssuedPerBdv,
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );
    }

    /**
     * @notice validates general whitelist functionality.
     */
    function test_whitelistTokenWithEncodeType(
        uint32 stalkEarnedPerSeason,
        uint32 stalkIssuedPerBdv,
        uint8 encodeType,
        uint128 gaugePoints,
        uint64 optimalPercentDepositedBdv
    ) public prank(BEANSTALK) {
        address token = address(new MockToken("Mock Token", "MTK"));
        bytes4 bdvSelector = IMockFBeanstalk.beanToBDV.selector;
        bytes4 gaugePointSelector = IMockFBeanstalk.defaultGaugePointFunction.selector;
        bytes4 liquidityWeightSelector = IMockFBeanstalk.maxWeight.selector;
        encodeType = encodeType % 2; // 0 or 1
        verifyWhitelistEvents(
            token,
            bdvSelector,
            stalkEarnedPerSeason,
            stalkIssuedPerBdv,
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );
        bs.whitelistTokenWithEncodeType(
            token,
            bdvSelector,
            stalkIssuedPerBdv,
            stalkEarnedPerSeason,
            bytes1(encodeType),
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );

        verifyWhitelistState(
            token,
            bdvSelector,
            stalkEarnedPerSeason,
            stalkIssuedPerBdv,
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );
    }

    function verifyWhitelistEvents(
        address token,
        bytes4 bdvSelector,
        uint32 stalkEarnedPerSeason,
        uint32 stalkIssuedPerBdv,
        bytes4 gaugePointSelector,
        bytes4 liquidityWeightSelector,
        uint128 gaugePoints,
        uint64 optimalPercentDepositedBdv
    ) public {
        vm.expectEmit();
        emit AddWhitelistStatus(token, 5, true, true, false);
        vm.expectEmit();
        emit WhitelistToken(
            token,
            bdvSelector,
            stalkEarnedPerSeason == 0 ? 1 : stalkEarnedPerSeason,
            stalkIssuedPerBdv,
            gaugePointSelector,
            liquidityWeightSelector,
            gaugePoints,
            optimalPercentDepositedBdv
        );
    }

    function verifyWhitelistState(
        address token,
        bytes4 bdvSelector,
        uint32 stalkEarnedPerSeason,
        uint32 stalkIssuedPerBdv,
        bytes4 gaugePointSelector,
        bytes4 liquidityWeightSelector,
        uint128 gaugePoints,
        uint64 optimalPercentDepositedBdv
    ) internal view {
        IMockFBeanstalk.AssetSettings memory ss = bs.tokenSettings(token);
        assertEq(ss.selector, bdvSelector);
        assertEq(uint256(ss.stalkIssuedPerBdv), stalkIssuedPerBdv);
        assertEq(
            uint256(ss.stalkEarnedPerSeason),
            stalkEarnedPerSeason == 0 ? 1 : stalkEarnedPerSeason
        );
        assertEq(uint256(ss.stalkIssuedPerBdv), stalkIssuedPerBdv);
        assertEq(ss.gpSelector, gaugePointSelector);
        assertEq(ss.lwSelector, liquidityWeightSelector);
        assertEq(uint256(ss.gaugePoints), gaugePoints);
        assertEq(uint256(ss.optimalPercentDepositedBdv), optimalPercentDepositedBdv);

        IMockFBeanstalk.WhitelistStatus memory ws = bs.getWhitelistStatus(token);
        assertEq(ws.token, token);
        assertEq(ws.isWhitelisted, true);
        assertEq(ws.isWhitelistedLp, true);
        assertEq(ws.isWhitelistedWell, false);
    }
}
