// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import {TestHelper} from "./utils/TestHelper.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {LibTransfer} from "contracts/libraries/Token/LibTransfer.sol";
import {IMockFBeanstalk} from "contracts/interfaces/IMockFBeanstalk.sol";
import {MockSeasonFacet} from "contracts/mocks/mockFacets/MockSeasonFacet.sol";
import {MockSiloFacet} from "contracts/mocks/mockFacets/MockSiloFacet.sol";
import {MockPump} from "contracts/mocks/well/MockPump.sol";
import {ConvertFacet} from "contracts/beanstalk/silo/ConvertFacet.sol";
import {Bean} from "contracts/tokens/Bean.sol";
import {IWell, Call} from "contracts/interfaces/basin/IWell.sol";
import {MockToken} from "contracts/mocks/MockToken.sol";
import {DepotFacet, AdvancedPipeCall} from "contracts/beanstalk/farm/DepotFacet.sol";
import {AdvancedFarmCall} from "contracts/libraries/LibFarm.sol";
import {C} from "contracts/C.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibWell} from "contracts/libraries/Well/LibWell.sol";
import {ICappedReservesPump} from "contracts/interfaces/basin/pumps/ICappedReservesPump.sol";
import {LibClipboard} from "contracts/libraries/LibClipboard.sol";
import {LibWellMinting} from "contracts/libraries/Minting/LibWellMinting.sol";
import {LibConvert} from "contracts/libraries/Convert/LibConvert.sol";
import "forge-std/Test.sol";

contract MiscHelperContract {
    function returnNumber(uint256 num) public pure returns (uint256) {
        return num;
    }
}

/**
 * @title PipelineConvertTest
 * @author pizzaman1337
 * @notice Test pipeline convert.
 */
contract PipelineConvertTest is TestHelper {
    using SafeMath for uint256;

    // Interfaces.
    // IMockFBeanstalk bs = IMockFBeanstalk(BEANSTALK);
    MockSiloFacet silo = MockSiloFacet(BEANSTALK);
    ConvertFacet convert = ConvertFacet(BEANSTALK);
    MockSeasonFacet season = MockSeasonFacet(BEANSTALK);
    DepotFacet depot = DepotFacet(BEANSTALK);
    MockToken bean = MockToken(C.BEAN);
    address beanEthWell = C.BEAN_ETH_WELL;
    address beanwstethWell = C.BEAN_WSTETH_WELL;
    MiscHelperContract miscHelper = new MiscHelperContract();

    // test accounts
    address[] farmers;

    uint256 constant MAX_UINT256 = type(uint256).max;
    uint256 constant BDV_TO_STALK = 1e4;

    bytes constant noData = abi.encode(0);

    struct PipelineTestData {
        address inputWell;
        address outputWell;
        uint256 wellAmountOut;
        uint256 grownStalkForDeposit;
        uint256 bdvOfAmountOut;
        int96 outputStem;
        address inputWellEthToken;
        address outputWellEthToken;
        int256 inputWellNewDeltaB;
        uint256 beansOut;
        int256 outputWellNewDeltaB;
        uint256 lpOut;
        uint256 beforeInputTokenLPSupply;
        uint256 afterInputTokenLPSupply;
        uint256 beforeOutputTokenLPSupply;
        uint256 afterOutputTokenLPSupply;
    }

    // Event defs

    event Convert(
        address indexed account,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    );

    event RemoveDeposits(
        address indexed account,
        address indexed token,
        int96[] stems,
        uint256[] amounts,
        uint256 amount,
        uint256[] bdvs
    );

    event AddDeposit(
        address indexed account,
        address indexed token,
        int96 stem,
        uint256 amount,
        uint256 bdv
    );

    function setUp() public {
        initializeBeanstalkTestState(true, false);

        // initalize farmers.
        farmers.push(users[1]);
        farmers.push(users[2]);

        // add inital liquidity to bean eth well:
        // prank beanstalk deployer (can be anyone)
        vm.prank(users[0]);
        addLiquidityToWell(
            beanEthWell,
            10000e6, // 10,000 bean,
            10 ether // 10 WETH
        );

        addLiquidityToWell(
            beanwstethWell,
            10000e6, // 10,000 bean,
            10 ether // 10 WETH of wstETH
        );

        // mint 1000 beans to farmers (user 0 is the beanstalk deployer).
        mintTokensToUsers(farmers, C.BEAN, MAX_DEPOSIT_BOUND);
    }

    //////////// CONVERTS ////////////

    function testBasicConvertBeanToLP(uint256 amount) public {
        vm.pauseGasMetering();
        int96 stem;

        amount = bound(amount, 10e6, 5000e6);

        // manipulate well so we won't have a penalty applied
        // TODO: add a test that also calculates proper penalty and verifies?
        setDeltaBforWell(int256(amount), beanEthWell, C.WETH);

        depositBeanAndPassGermination(amount, users[1]);

        // do the convert

        // Create arrays for stem and amount
        int96[] memory stems = new int96[](1);
        stems[0] = stem;

        AdvancedFarmCall[] memory beanToLPFarmCalls = createBeanToLPFarmCalls(
            amount,
            new AdvancedPipeCall[](0)
        );

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // get well amount out if we deposit amount of beans
        uint256 wellAmountOut = getWellAmountOutForAddingBeans(amount);

        uint256 grownStalkForDeposit = bs.grownStalkForDeposit(users[1], C.BEAN, stem);

        uint256 bdvOfAmountOut = bs.bdv(beanEthWell, wellAmountOut);
        (int96 outputStem, ) = bs.calculateStemForTokenFromGrownStalk(
            beanEthWell,
            grownStalkForDeposit,
            bdvOfAmountOut
        );

        vm.expectEmit(true, false, false, true);
        emit RemoveDeposits(users[1], C.BEAN, stems, amounts, amount, amounts);

        vm.expectEmit(true, false, false, true);
        emit AddDeposit(users[1], beanEthWell, outputStem, wellAmountOut, bdvOfAmountOut);

        // verify convert
        vm.expectEmit(true, false, false, true);
        emit Convert(users[1], C.BEAN, beanEthWell, amount, wellAmountOut);

        vm.resumeGasMetering();
        vm.prank(users[1]); // do this as user 1
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stems
            amounts, // amount
            beanEthWell, // token out
            beanToLPFarmCalls // farmData
        );
    }

    function testBasicConvertLPToBean(uint256 amount) public {
        vm.pauseGasMetering();

        // well is initalized with 10000 beans. cap add liquidity
        // to reasonable amounts.
        amount = bound(amount, 1e6, 10000e6);

        (int96 stem, uint256 lpAmountOut) = depositLPAndPassGermination(amount);

        // Create arrays for stem and amount. Tried just passing in [stem] and it's like nope.
        int96[] memory stems = new int96[](1);
        stems[0] = stem;

        AdvancedFarmCall[] memory beanToLPFarmCalls = createLPToBeanFarmCalls(lpAmountOut);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmountOut;

        // todo: add events verification

        vm.resumeGasMetering();
        vm.prank(users[1]); // do this as user 1
        convert.pipelineConvert(
            beanEthWell, // input token
            stems, // stems
            amounts, // amount
            C.BEAN, // token out
            beanToLPFarmCalls // farmData
        );
    }

    function testConvertLPToLP(uint256 amount, uint256 direction) public {
        vm.pauseGasMetering();

        // well is initalized with 10000 beans. cap add liquidity
        // to reasonable amounts.
        amount = bound(amount, 5000e6, 5000e6);

        // 0 is from bean:eth well
        // 1 is from bean:wsteth well
        direction = bound(direction, 0, 1);

        PipelineTestData memory pd;

        pd.inputWell = direction == 0 ? beanEthWell : beanwstethWell;
        pd.outputWell = direction == 0 ? beanwstethWell : beanEthWell;

        console.log("inputWell: ", pd.inputWell);
        console.log("outputWell: ", pd.outputWell);

        pd.inputWellEthToken = direction == 0 ? C.WETH : C.WSTETH;
        pd.outputWellEthToken = direction == 0 ? C.WSTETH : C.WETH;

        // log overall deltaB
        console.log("overall deltaB: ");
        console.logInt(LibWellMinting.overallCurrentDeltaB());

        // update pumps
        updateMockPumpUsingWellReserves(pd.inputWell);
        updateMockPumpUsingWellReserves(pd.outputWell);

        (int96 stem, uint256 amountOfDepositedLP) = depositLPAndPassGermination(amount);
        uint256 bdvOfDepositedLp = bs.bdv(pd.inputWell, amountOfDepositedLP);
        uint256[] memory bdvAmountsDeposited = new uint256[](1);
        bdvAmountsDeposited[0] = bdvOfDepositedLp;

        // modify deltaB's so that the user already owns LP token, and then perfectly even deltaB's are setup
        setDeltaBforWell(-int256(amount), pd.inputWell, pd.inputWellEthToken);
        // return;

        setDeltaBforWell(int256(amount), pd.outputWell, pd.outputWellEthToken);

        // now log deltaB's?
        // console.log("inputWell deltaB: ");
        // console.logInt(bs.poolCurrentDeltaB(inputWell));
        // console.log("outputWell deltaB: ");
        // console.logInt(bs.poolCurrentDeltaB(outputWell));
        // return;

        // log deltaB for this well before convert
        // int256 beforeDeltaBEth = bs.poolCurrentDeltaB(beanEthWell);
        // int256 beforeDeltaBwsteth = bs.poolCurrentDeltaB(beanwstethWell);

        // uint256 beforeGrownStalk = bs.balanceOfGrownStalk(users[1], beanEthWell);
        uint256 beforeBalanceOfStalk = bs.balanceOfStalk(users[1]);

        int96[] memory stems = new int96[](1);
        stems[0] = stem;

        AdvancedFarmCall[] memory lpToLPFarmCalls = createLPToLPFarmCalls(
            amountOfDepositedLP,
            pd.inputWell
        );

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountOfDepositedLP;

        pd.wellAmountOut = getWellAmountOutFromLPtoLP(
            amountOfDepositedLP,
            pd.inputWell,
            pd.outputWell
        );
        console.log("pd.wellAmountOut: ", pd.wellAmountOut);
        pd.grownStalkForDeposit = bs.grownStalkForDeposit(users[1], pd.inputWell, stem);
        console.log("pd.grownStalkForDeposit: ", pd.grownStalkForDeposit);
        pd.bdvOfAmountOut = bs.bdv(pd.outputWell, pd.wellAmountOut);
        console.log("pd.bdvOfAmountOut: ", pd.bdvOfAmountOut);
        (pd.outputStem, ) = bs.calculateStemForTokenFromGrownStalk(
            pd.outputWell,
            pd.grownStalkForDeposit,
            pd.bdvOfAmountOut
        );

        // calculate new reserves for well using get swap out and manually figure out what deltaB would be
        (pd.inputWellNewDeltaB, pd.beansOut) = calculateDeltaBForWellAfterSwapFromLP(
            amountOfDepositedLP,
            pd.inputWell
        );

        (pd.outputWellNewDeltaB, pd.lpOut) = calculateDeltaBForWellAfterSwapFromBean(
            pd.beansOut,
            pd.outputWell
        );

        pd.beforeInputTokenLPSupply = IERC20(pd.inputWell).totalSupply();
        pd.afterInputTokenLPSupply = pd.beforeInputTokenLPSupply.sub(amountOfDepositedLP);
        pd.beforeOutputTokenLPSupply = IERC20(pd.outputWell).totalSupply();
        pd.afterOutputTokenLPSupply = pd.beforeOutputTokenLPSupply.add(pd.lpOut);

        LibConvert.DeltaBStorage memory dbs;

        dbs.beforeInputTokenDeltaB = LibWellMinting.currentDeltaB(pd.inputWell);
        dbs.afterInputTokenDeltaB = LibWellMinting.scaledDeltaB(
            pd.beforeInputTokenLPSupply,
            pd.afterInputTokenLPSupply,
            pd.inputWellNewDeltaB
        );
        dbs.beforeOutputTokenDeltaB = LibWellMinting.currentDeltaB(pd.outputWell);
        dbs.afterOutputTokenDeltaB = LibWellMinting.scaledDeltaB(
            pd.beforeOutputTokenLPSupply,
            pd.afterOutputTokenLPSupply,
            pd.outputWellNewDeltaB
        );
        dbs.beforeOverallDeltaB = LibWellMinting.overallCurrentDeltaB();
        dbs.afterOverallDeltaB = 0; // update and for scaled deltaB

        // todo: calculateStalkPenalty and subtract penalty from grown stalk, which affects pd.outputStem

        // console.log("pd.outputStem: ");
        // console.logInt(pd.outputStem);

        vm.expectEmit(true, false, false, true);
        emit RemoveDeposits(
            users[1],
            pd.inputWell,
            stems,
            amounts,
            amountOfDepositedLP,
            bdvAmountsDeposited
        );

        vm.expectEmit(true, false, false, true);
        emit AddDeposit(
            users[1],
            pd.outputWell,
            pd.outputStem,
            pd.wellAmountOut,
            pd.bdvOfAmountOut
        );

        // verify convert
        vm.expectEmit(true, false, false, true);
        emit Convert(users[1], pd.inputWell, pd.outputWell, amountOfDepositedLP, pd.wellAmountOut);

        vm.resumeGasMetering();
        vm.prank(users[1]);

        convert.pipelineConvert(
            pd.inputWell, // input token
            stems, // stems
            amounts, // amount
            pd.outputWell, // token out
            lpToLPFarmCalls // farmData
        );

        console.log("inputWellNewDeltaB: ");
        console.logInt(pd.inputWellNewDeltaB);
        console.log("outputWellNewDeltaB: ");
        console.logInt(pd.outputWellNewDeltaB);

        // int256 afterDeltaBEth = bs.poolCurrentDeltaB(inputWell);
        // int256 afterDeltaBwsteth = bs.poolCurrentDeltaB(outputWell);

        // // make sure deltaB's moved in the way we expect them to
        // assertTrue(beforeDeltaBEth < afterDeltaBEth);
        // assertTrue(afterDeltaBwsteth < beforeDeltaBwsteth);

        // uint256 totalStalkAfter = bs.balanceOfStalk(users[1]);

        // since we didn't cross peg and there was convert power, we expect full remaining grown stalk
        // (plus a little from the convert benefit)
        // assertTrue(totalStalkAfter >= beforeBalanceOfStalk);
    }

    function testUpdatingOverallDeltaB(uint256 amount) public {
        amount = bound(amount, 1e6, 5000e6);
        depositLPAndPassGermination(amount);
        mineBlockAndUpdatePumps();

        int256 overallCappedDeltaB = bs.overallCappedDeltaB();
        assertTrue(overallCappedDeltaB != 0);
    }

    function testDeltaBChangeBeanToLP(uint256 amount) public {
        amount = bound(amount, 1e6, 5000e6);
        int256 beforeDeltaB = bs.poolCurrentDeltaB(beanEthWell);

        doBasicBeanToLP(amount, users[1]);

        int256 afterDeltaB = bs.poolCurrentDeltaB(beanEthWell);
        assertTrue(afterDeltaB < beforeDeltaB);
        assertTrue(beforeDeltaB - int256(amount) * 2 < afterDeltaB);
        // would be great to calcuate exactly what the new deltaB should be after convert
    }

    function testTotalStalkAmountDidNotIncrease(uint256 amount) public {
        amount = bound(amount, 1e6, 5000e6);
        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        uint256 beforeTotalStalk = bs.totalStalk();
        beanToLPDoConvert(amount, stem, users[1]);

        uint256 afterTotalStalk = bs.totalStalk();
        assertTrue(afterTotalStalk <= beforeTotalStalk);
    }

    function testUserStalkAmountDidNotIncrease(uint256 amount) public {
        amount = bound(amount, 1e6, 5000e6);
        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        uint256 beforeUserStalk = bs.balanceOfStalk(users[1]);
        beanToLPDoConvert(amount, stem, users[1]);

        uint256 afterUserStalk = bs.balanceOfStalk(users[1]);
        assertTrue(afterUserStalk <= beforeUserStalk);
    }

    function testUserBDVDidNotIncrease(uint256 amount) public {
        amount = bound(amount, 1e6, 5000e6);
        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        uint256 beforeUserDeposit = bs.balanceOfDepositedBdv(users[1], C.BEAN);
        beanToLPDoConvert(amount, stem, users[1]);

        uint256 afterUserDeposit = bs.balanceOfDepositedBdv(users[1], C.BEAN);
        assertTrue(afterUserDeposit <= beforeUserDeposit);
    }

    function testConvertAgainstPegAndLoseStalk(uint256 amount) public {
        amount = bound(amount, 5000e6, 5000e6); // todo: update for range

        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        // uint256 beforeTotalStalk = bs.totalStalk();
        uint256 grownStalkBefore = bs.balanceOfGrownStalk(users[1], C.BEAN);

        beanToLPDoConvert(amount, stem, users[1]);

        uint256 grownStalkAfter = bs.balanceOfGrownStalk(users[1], beanEthWell);

        assertTrue(grownStalkAfter == 0); // all grown stalk was lost
        assertTrue(grownStalkBefore > 0);
    }

    function testConvertWithPegAndKeepStalk(uint256 amount) public {
        amount = bound(amount, 10e6, 5000e6);

        setDeltaBforWell(int256(amount), beanEthWell, C.WETH);

        // how many eth would we get if we swapped this amount in the well
        uint256 ethAmount = IWell(beanEthWell).getSwapOut(IERC20(C.BEAN), IERC20(C.WETH), amount);

        MockToken(C.WETH).mint(users[1], ethAmount);
        vm.prank(users[1]);
        MockToken(C.WETH).approve(beanEthWell, ethAmount);

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = 0;
        tokenAmountsIn[1] = ethAmount;

        vm.prank(users[1]);
        IWell(beanEthWell).addLiquidity(tokenAmountsIn, 0, users[1], type(uint256).max);

        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        uint256 grownStalkBefore = bs.balanceOfGrownStalk(users[1], C.BEAN);

        beanToLPDoConvert(amount, stem, users[1]);

        uint256 totalStalkAfter = bs.balanceOfStalk(users[1]);

        // get balance of deposited bdv for this user
        uint256 bdvBalance = bs.balanceOfDepositedBdv(users[1], beanEthWell) * BDV_TO_STALK; // convert to stalk amount

        assertTrue(totalStalkAfter == bdvBalance + grownStalkBefore); // all grown stalk was kept
    }

    function testFlashloanManipulationLoseGrownStalkBecauseZeroConvertCapacity(
        uint256 amount
    ) public {
        amount = bound(amount, 5000e6, 5000e6); // todo: update for range

        // the main idea is that we start at deltaB of zero, so converts should not be possible
        // we add eth to the well to push it over peg, then we convert our beans back down to lp
        // then we pull our initial eth back out and we converted when we shouldn't have been able to (if we do in one tx)

        // setup initial bean deposit
        int96 stem = depositBeanAndPassGermination(amount, users[1]);

        // mint user 10 eth
        uint256 ethAmount = 10e18;
        MockToken(C.WETH).mint(users[1], ethAmount);

        vm.prank(users[1]);
        MockToken(C.WETH).approve(beanEthWell, ethAmount);

        // add liquidity to well
        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = 0;
        tokenAmountsIn[1] = ethAmount;

        vm.prank(users[1]);
        IWell(beanEthWell).addLiquidity(tokenAmountsIn, 0, users[1], type(uint256).max);

        uint256 grownStalkBefore = bs.balanceOfGrownStalk(users[1], C.BEAN);

        // convert beans to lp
        beanToLPDoConvert(amount, stem, users[1]);

        // it should be that we lost our grown stalk from this convert

        uint256 grownStalkAfter = bs.balanceOfGrownStalk(users[1], beanEthWell);

        assertTrue(grownStalkAfter == 0); // all grown stalk was lost
        assertTrue(grownStalkBefore > 0);
    }

    // double convert uses up convert power so we should be left at no grown stalk after second convert
    // (but still have grown stalk after first convert)
    function testFlashloanManipulationLoseGrownStalkBecauseDoubleConvert(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6); // todo: update for range

        // do initial pump update
        updateMockPumpUsingWellReserves(beanEthWell);

        // the main idea is that we start some positive deltaB, so a limited amount of converts are possible (1.2 eth worth)
        // User One does a convert down, and that uses up convert power for this block
        // someone adds more eth to the well, which means we're back too far over peg
        // then User Two tries to do a convert down, but at that point the convert power has been used up, so they lose their grown stalk

        // setup initial bean deposit
        int96 stem = depositBeanAndPassGermination(amount, users[1]);

        // then setup a convert from user 2
        int96 stem2 = depositBeanAndPassGermination(amount, users[2]);

        // if you deposited amount of beans into well, how many eth would you get?
        uint256 ethAmount = IWell(beanEthWell).getSwapOut(IERC20(C.BEAN), IERC20(C.WETH), amount);

        ethAmount = ethAmount.mul(12000).div(10000); // I need a better way to calculate how much eth out there should be to make sure we can swap and be over peg

        addEthToWell(users[1], ethAmount);

        // go to next block
        vm.roll(block.number + 1);

        uint256 grownStalkBefore = bs.balanceOfGrownStalk(users[2], C.BEAN);

        // update pump
        updateMockPumpUsingWellReserves(beanEthWell);

        // convert.cappedReservesDeltaB(beanEthWell);

        uint256 convertCapacityStage1 = convert.getConvertCapacity();

        // convert beans to lp
        beanToLPDoConvert(amount, stem, users[1]);

        uint256 convertCapacityStage2 = convert.getConvertCapacity();
        assertTrue(convertCapacityStage2 < convertCapacityStage1);

        // add more eth to well again
        addEthToWell(users[1], ethAmount);

        beanToLPDoConvert(amount, stem2, users[2]);

        uint256 convertCapacityStage3 = convert.getConvertCapacity();
        assertTrue(convertCapacityStage3 < convertCapacityStage2);

        uint256 grownStalkAfter = bs.balanceOfGrownStalk(users[2], beanEthWell);

        assertTrue(grownStalkAfter == 0); // all grown stalk was lost because no convert power left
        assertTrue(grownStalkBefore > 0);
    }

    function testConvertingOutputTokenNotWell(uint256 amount) public {
        amount = bound(amount, 1, 1000e6);
        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        AdvancedFarmCall[] memory beanToLPFarmCalls = createBeanToLPFarmCalls(
            amount,
            new AdvancedPipeCall[](0)
        );
        vm.expectRevert("Convert: Output token must be Bean or a well");
        // convert non-whitelisted asset to lp
        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            C.UNRIPE_LP, // token out
            beanToLPFarmCalls // farmData
        );
    }

    function testConvertingInputTokenNotWell(uint256 amount) public {
        amount = bound(amount, 1, 1000e6);
        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        AdvancedFarmCall[] memory beanToLPFarmCalls = createBeanToLPFarmCalls(
            amount,
            new AdvancedPipeCall[](0)
        );
        vm.expectRevert("Convert: Input token must be Bean or a well");
        // convert non-whitelisted asset to lp
        vm.prank(users[1]);
        convert.pipelineConvert(
            C.UNRIPE_LP, // input token
            stems, // stem
            amounts, // amount
            C.BEAN, // token out
            beanToLPFarmCalls // farmData
        );
    }

    // test that leaves less ERC20 in the pipeline than is returned by the final function
    // no longer necessary since we now check how many tokens were left in pipeline, leaving here in case it can be repurposed
    /*function testNotEnoughTokensLeftInPipeline(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6);
        int96 stem = beanToLPDepositSetup(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 returnThisNumber = 5000e22;

        bytes memory returnNumberEncoded = abi.encodeWithSelector(
            MiscHelperContract.returnNumber.selector,
            returnThisNumber
        );

        // create extra pipe calls
        AdvancedPipeCall[] memory extraPipeCalls = new AdvancedPipeCall[](1);
        // extra call will be to a function that returns a big number (more than amoutn of LP left in pipeline)
        extraPipeCalls[0] = AdvancedPipeCall(
            address(miscHelper), // target
            returnNumberEncoded, // calldata
            abi.encode(0) // clipboard
        );

        AdvancedFarmCall[] memory beanToLPFarmCalls = createBeanToLPFarmCalls(amount, extraPipeCalls);

        vm.expectRevert("ERC20: transfer amount exceeds balance");

        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            beanEthWell, // token out
            beanToLPFarmCalls // farmData
        );
    }*/

    function testBeanToBeanConvert(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6);

        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 stalkBefore = bs.balanceOfStalk(users[1]);
        uint256 grownStalk = bs.grownStalkForDeposit(users[1], C.BEAN, stem);

        // make a pipeline call where the only thing it does is return how many beans are in pipeline
        bytes memory callEncoded = abi.encodeWithSelector(bean.balanceOf.selector, C.PIPELINE);
        AdvancedPipeCall[] memory extraPipeCalls = new AdvancedPipeCall[](1);
        extraPipeCalls[0] = AdvancedPipeCall(
            C.BEAN, // target
            callEncoded, // calldata
            abi.encode(0) // clipboard
        );

        AdvancedFarmCall[] memory farmCalls = createAdvancedFarmCallsFromAdvancedPipeCalls(
            extraPipeCalls
        );

        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            C.BEAN, // token out
            farmCalls
        );

        uint256 stalkAfter = bs.balanceOfStalk(users[1]);
        assertEq(stalkAfter, stalkBefore + grownStalk);
    }

    // half of the bdv is extracted during the convert, stalk/bdv of deposits should be correct on output
    function testBeanToBeanConvertLessBdv(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6);

        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 stalkBefore = bs.balanceOfStalk(users[1]);
        uint256 grownStalk = bs.grownStalkForDeposit(users[1], C.BEAN, stem);
        uint256 bdvBefore = bs.balanceOfDepositedBdv(users[1], C.BEAN);

        // make a pipeline call where the only thing it does is return how many beans are in pipeline
        AdvancedPipeCall[] memory extraPipeCalls = new AdvancedPipeCall[](1);

        // send half our beans from pipeline to Vitalik address (for some reason zero address gave an evm error)
        bytes memory sendBeans = abi.encodeWithSelector(
            bean.transfer.selector,
            0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045,
            amount.div(2)
        );
        extraPipeCalls[0] = AdvancedPipeCall(
            C.BEAN, // target
            sendBeans, // calldata
            abi.encode(0) // clipboard
        );

        AdvancedFarmCall[] memory farmCalls = createAdvancedFarmCallsFromAdvancedPipeCalls(
            extraPipeCalls
        );

        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            C.BEAN, // token out
            farmCalls
        );

        uint256 stalkAfter = bs.balanceOfStalk(users[1]);
        assertEq(stalkAfter, stalkBefore.div(2) + grownStalk);

        uint256 bdvAfter = bs.balanceOfDepositedBdv(users[1], C.BEAN);
        assertEq(bdvAfter, bdvBefore.div(2));
    }

    // adds 50% more beans to the pipeline so we get extra bdv after convert
    function testBeanToBeanConvertMoreBdv(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6);

        // mint extra beans to pipeline so we can snatch them on convert back into beanstalk
        bean.mint(C.PIPELINE, amount.div(2));

        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 stalkBefore = bs.balanceOfStalk(users[1]);
        uint256 grownStalk = bs.grownStalkForDeposit(users[1], C.BEAN, stem);
        uint256 bdvBefore = bs.balanceOfDepositedBdv(users[1], C.BEAN);

        // make a pipeline call where the only thing it does is return how many beans are in pipeline
        AdvancedPipeCall[] memory extraPipeCalls = new AdvancedPipeCall[](1);

        bytes memory callEncoded = abi.encodeWithSelector(bean.balanceOf.selector, C.PIPELINE);
        extraPipeCalls[0] = AdvancedPipeCall(
            C.BEAN, // target
            callEncoded, // calldata
            abi.encode(0) // clipboard
        );

        AdvancedFarmCall[] memory farmCalls = createAdvancedFarmCallsFromAdvancedPipeCalls(
            extraPipeCalls
        );

        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            C.BEAN, // token out
            farmCalls
        );

        uint256 stalkAfter = bs.balanceOfStalk(users[1]);
        assertEq(stalkAfter, stalkBefore + stalkBefore.div(2) + grownStalk);

        uint256 bdvAfter = bs.balanceOfDepositedBdv(users[1], C.BEAN);
        assertEq(bdvAfter, bdvBefore + bdvBefore.div(2));
    }

    function testBeanToBeanConvertNoneLeftInPipeline(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6);

        int96 stem = depositBeanAndPassGermination(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        AdvancedPipeCall[] memory extraPipeCalls = new AdvancedPipeCall[](1);

        // send all our beans away
        bytes memory sendBeans = abi.encodeWithSelector(
            bean.transfer.selector,
            0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045,
            amount
        );
        extraPipeCalls[0] = AdvancedPipeCall(
            C.BEAN, // target
            sendBeans, // calldata
            abi.encode(0) // clipboard
        );

        AdvancedFarmCall[] memory farmCalls = createAdvancedFarmCallsFromAdvancedPipeCalls(
            extraPipeCalls
        );

        vm.expectRevert("Convert: No output tokens left in pipeline");
        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            C.BEAN, // token out
            farmCalls
        );
    }

    // test bean to bean convert, but deltaB is affected against them and there is convert power left in the block
    // because the deltaB of "bean" is not affected, no stalk loss should occur
    /*function testBeanToBeanConvertAffectDeltaB(uint256 amount) public {
        amount = bound(amount, 1000e6, 1000e6);

        int96 stem = beanToLPDepositSetup(amount, users[1]);
        int96[] memory stems = new int96[](1);
        stems[0] = stem;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // mint a weth to pipeline for later use
        uint256 ethAmount = 1 ether;
        MockToken(C.WETH).mint(C.PIPELINE, ethAmount);

        addEthToWell(users[1], 1 ether);

        updateMockPumpUsingWellReserves(beanEthWell);

        // move foward 10 seasons so we have grown stalk
        season.siloSunrise(10);

        // store stalk before
        uint256 beforeStalk = bs.balanceOfStalk(users[1]) + bs.grownStalkForDeposit(users[1], C.BEAN, stem);

        // make a pipeline call where the only thing it does is return how many beans are in pipeline
        AdvancedPipeCall[] memory extraPipeCalls = new AdvancedPipeCall[](2);

        bytes memory approveWell = abi.encodeWithSelector(
            IERC20.approve.selector,
            beanEthWell,
            ethAmount
        );
        extraPipeCalls[0] = AdvancedPipeCall(
            C.WETH, // target
            approveWell, // calldata
            abi.encode(0) // clipboard
        );

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = 0;
        tokenAmountsIn[1] = ethAmount;

        // add a weth to the well to affect deltaB
        bytes memory addWeth = abi.encodeWithSelector(
            IWell(beanEthWell).addLiquidity.selector,
            tokenAmountsIn,
            0,
            C.PIPELINE,
            type(uint256).max
        );
        extraPipeCalls[1] = AdvancedPipeCall(
            beanEthWell, // target
            addWeth, // calldata
            abi.encode(0) // clipboard
        );

        AdvancedFarmCall[] memory farmCalls = createAdvancedFarmCallsFromAdvancedPipeCalls(extraPipeCalls);

        vm.prank(users[1]);
        convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stem
            amounts, // amount
            C.BEAN, // token out
            farmCalls
        );

        // after stalk
        uint256 afterStalk = bs.balanceOfStalk(users[1]);

        // check that the deltaB is correct
        assertEq(afterStalk, beforeStalk);
    }*/

    // bonus todo: setup a test that reads remaining convert power from block and uses it when determining how much to convert
    // there are already tests that exercise depleting convert power, but might be cool to show how you can use it in a convert

    function testAmountAgainstPeg() public {
        uint256 amountAgainstPeg;
        uint256 crossoverAmount;

        (amountAgainstPeg) = LibConvert.calculateAmountAgainstPeg(-500, -400);
        assertEq(amountAgainstPeg, 0);

        (amountAgainstPeg) = LibConvert.calculateAmountAgainstPeg(-100, 0);
        assertEq(amountAgainstPeg, 0);

        (amountAgainstPeg) = LibConvert.calculateAmountAgainstPeg(100, 0);
        assertEq(amountAgainstPeg, 0);

        (amountAgainstPeg) = LibConvert.calculateAmountAgainstPeg(1, 101);
        assertEq(amountAgainstPeg, 100);

        (amountAgainstPeg) = LibConvert.calculateAmountAgainstPeg(0, 100);
        assertEq(amountAgainstPeg, 100);

        (amountAgainstPeg) = LibConvert.calculateAmountAgainstPeg(0, -100);
        assertEq(amountAgainstPeg, 100);
    }

    function testCalculateConvertedTowardsPeg() public {
        int256 beforeDeltaB = -100;
        int256 afterDeltaB = 0;
        uint256 amountInDirectionOfPeg = LibConvert.calculateConvertedTowardsPeg(
            beforeDeltaB,
            afterDeltaB
        );
        assertEq(amountInDirectionOfPeg, 100);

        beforeDeltaB = 100;
        afterDeltaB = 0;
        amountInDirectionOfPeg = LibConvert.calculateConvertedTowardsPeg(beforeDeltaB, afterDeltaB);
        assertEq(amountInDirectionOfPeg, 100);

        beforeDeltaB = -50;
        afterDeltaB = 50;
        amountInDirectionOfPeg = LibConvert.calculateConvertedTowardsPeg(beforeDeltaB, afterDeltaB);
        assertEq(amountInDirectionOfPeg, 50);

        beforeDeltaB = 50;
        afterDeltaB = -50;
        amountInDirectionOfPeg = LibConvert.calculateConvertedTowardsPeg(beforeDeltaB, afterDeltaB);
        assertEq(amountInDirectionOfPeg, 50);

        beforeDeltaB = 0;
        afterDeltaB = 100;
        amountInDirectionOfPeg = LibConvert.calculateConvertedTowardsPeg(beforeDeltaB, afterDeltaB);
        assertEq(amountInDirectionOfPeg, 0);

        beforeDeltaB = 0;
        afterDeltaB = -100;
        amountInDirectionOfPeg = LibConvert.calculateConvertedTowardsPeg(beforeDeltaB, afterDeltaB);
        assertEq(amountInDirectionOfPeg, 0);
    }

    function testCalculateStalkPenaltyUpwardsToZero() public {
        addEthToWell(users[1], 1 ether);
        // Update the pump so that eth added above is reflected.
        updateMockPumpUsingWellReserves(beanEthWell);

        LibConvert.DeltaBStorage memory dbs;
        dbs.beforeOverallDeltaB = -100;
        dbs.afterOverallDeltaB = 0;
        dbs.beforeInputTokenDeltaB = -100;
        dbs.afterInputTokenDeltaB = 0;
        dbs.beforeOutputTokenDeltaB = 0;
        dbs.afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallConvertCapacity = 100;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        (uint256 penalty, , , ) = LibConvert.calculateStalkPenalty(
            dbs,
            bdvConverted,
            overallConvertCapacity,
            inputToken,
            outputToken
        );
        assertEq(penalty, 0);
    }

    function testCalculateConvertCapacityPenalty() public {
        addEthToWell(users[1], 1 ether);
        // Update the pump so that eth added above is reflected.
        updateMockPumpUsingWellReserves(beanEthWell);

        uint256 overallCappedDeltaB = 100;
        uint256 overallAmountInDirectionOfPeg = 100;
        address inputToken = beanEthWell;
        uint256 inputTokenAmountInDirectionOfPeg = 100;
        address outputToken = C.BEAN;
        uint256 outputTokenAmountInDirectionOfPeg = 100;
        (uint256 penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 0);

        // test with zero capped deltaB
        overallCappedDeltaB = 0;
        overallAmountInDirectionOfPeg = 100;
        inputToken = beanEthWell;
        inputTokenAmountInDirectionOfPeg = 100;
        outputToken = C.BEAN;
        outputTokenAmountInDirectionOfPeg = 100;
        (penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 100);
    }

    function testCalculateConvertCapacityPenaltyZeroOverallAmountInDirectionOfPeg() public {
        // test with zero overall amount in direction of peg
        uint256 overallCappedDeltaB = 100;
        uint256 overallAmountInDirectionOfPeg = 0;
        address inputToken = beanEthWell;
        uint256 inputTokenAmountInDirectionOfPeg = 0;
        address outputToken = C.BEAN;
        uint256 outputTokenAmountInDirectionOfPeg = 0;
        (uint256 penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 0);
    }

    function testOnePositivePoolOneNegativeZeroOverallDeltaB() public {
        uint256 overallCappedDeltaB = 0;
        uint256 overallAmountInDirectionOfPeg = 0;
        address inputToken = beanEthWell;
        uint256 inputTokenAmountInDirectionOfPeg = 0;
        address outputToken = C.BEAN;
        uint256 outputTokenAmountInDirectionOfPeg = 0;
        (uint256 penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 0);

        overallCappedDeltaB = 0;
        overallAmountInDirectionOfPeg = 0;
        inputToken = beanEthWell;
        inputTokenAmountInDirectionOfPeg = 100;
        outputToken = C.BEAN;
        outputTokenAmountInDirectionOfPeg = 0;
        (penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 100);
    }

    function testCalculateConvertCapacityPenaltyCapZeroInputToken() public {
        // test with input token zero convert capacity
        uint256 overallCappedDeltaB = 100;
        uint256 overallAmountInDirectionOfPeg = 100;
        address inputToken = beanEthWell;
        uint256 inputTokenAmountInDirectionOfPeg = 100;
        address outputToken = C.BEAN;
        uint256 outputTokenAmountInDirectionOfPeg = 0;
        (uint256 penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 100);
    }

    function testCalculateConvertCapacityPenaltyCapZeroOutputToken() public {
        // test with input token zero convert capacity
        uint256 overallCappedDeltaB = 100;
        uint256 overallAmountInDirectionOfPeg = 100;
        address inputToken = C.BEAN;
        uint256 inputTokenAmountInDirectionOfPeg = 0;
        address outputToken = beanEthWell;
        uint256 outputTokenAmountInDirectionOfPeg = 100;
        (uint256 penalty, , , ) = LibConvert.calculateConvertCapacityPenalty(
            overallCappedDeltaB,
            overallAmountInDirectionOfPeg,
            inputToken,
            inputTokenAmountInDirectionOfPeg,
            outputToken,
            outputTokenAmountInDirectionOfPeg
        );
        assertEq(penalty, 100);
    }

    /*
    function testCalculateStalkPenaltyUpwardsToZero() public {
        int256 beforeOverallDeltaB = -100;
        int256 afterOverallDeltaB = 0;
        int256 beforeInputTokenDeltaB = -100;
        int256 beforeOutputTokenDeltaB = 0;
        int256 afterInputTokenDeltaB = 0;
        int256 afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallCappedDeltaB = 100;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        uint256 penalty = LibConvert.calculateStalkPenalty(
            beforeOverallDeltaB,
            afterOverallDeltaB,
            beforeInputTokenDeltaB,
            beforeOutputTokenDeltaB,
            afterInputTokenDeltaB,
            afterOutputTokenDeltaB,
            bdvConverted,
            overallCappedDeltaB,
            inputToken,
            outputToken
        );
        assertEq(penalty, 0);
    }

    function testCalculateStalkPenaltyUpwardsNonZero() public {
        int256 beforeOverallDeltaB = -200;
        int256 afterOverallDeltaB = -100;
        int256 beforeInputTokenDeltaB = -100;
        int256 beforeOutputTokenDeltaB = 0;
        int256 afterInputTokenDeltaB = 0;
        int256 afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallCappedDeltaB = 100;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        uint256 penalty = LibConvert.calculateStalkPenalty(
            beforeOverallDeltaB,
            afterOverallDeltaB,
            beforeInputTokenDeltaB,
            beforeOutputTokenDeltaB,
            afterInputTokenDeltaB,
            afterOutputTokenDeltaB,
            bdvConverted,
            overallCappedDeltaB,
            inputToken,
            outputToken
        );
        assertEq(penalty, 0);
    }

    function testCalculateStalkPenaltyDownwardsToZero() public {
        int256 beforeOverallDeltaB = 100;
        int256 afterOverallDeltaB = 0;
        int256 beforeInputTokenDeltaB = -100;
        int256 beforeOutputTokenDeltaB = 0;
        int256 afterInputTokenDeltaB = 0;
        int256 afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallCappedDeltaB = 100;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        uint256 penalty = LibConvert.calculateStalkPenalty(
            beforeOverallDeltaB,
            afterOverallDeltaB,
            beforeInputTokenDeltaB,
            beforeOutputTokenDeltaB,
            afterInputTokenDeltaB,
            afterOutputTokenDeltaB,
            bdvConverted,
            overallCappedDeltaB,
            inputToken,
            outputToken
        );
        assertEq(penalty, 0);
    }

    function testCalculateStalkPenaltyDownwardsNonZero() public {
        int256 beforeOverallDeltaB = 200;
        int256 afterOverallDeltaB = 100;
        int256 beforeInputTokenDeltaB = -100;
        int256 beforeOutputTokenDeltaB = 0;
        int256 afterInputTokenDeltaB = 0;
        int256 afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallCappedDeltaB = 100;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        uint256 penalty = LibConvert.calculateStalkPenalty(
            beforeOverallDeltaB,
            afterOverallDeltaB,
            beforeInputTokenDeltaB,
            beforeOutputTokenDeltaB,
            afterInputTokenDeltaB,
            afterOutputTokenDeltaB,
            bdvConverted,
            overallCappedDeltaB,
            inputToken,
            outputToken
        );
        assertEq(penalty, 0);
    }

    function testCalculateStalkPenaltyCrossPegUpward() public {
        int256 beforeOverallDeltaB = -50;
        int256 afterOverallDeltaB = 50;
        int256 beforeInputTokenDeltaB = -100;
        int256 beforeOutputTokenDeltaB = 0;
        int256 afterInputTokenDeltaB = 0;
        int256 afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallCappedDeltaB = 50;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        uint256 penalty = LibConvert.calculateStalkPenalty(
            beforeOverallDeltaB,
            afterOverallDeltaB,
            beforeInputTokenDeltaB,
            beforeOutputTokenDeltaB,
            afterInputTokenDeltaB,
            afterOutputTokenDeltaB,
            bdvConverted,
            overallCappedDeltaB,
            inputToken,
            outputToken
        );
        assertEq(penalty, 50);
    }

    function testCalculateStalkPenaltyCrossPegDownward() public {
        int256 beforeOverallDeltaB = 50;
        int256 afterOverallDeltaB = -50;
        int256 beforeInputTokenDeltaB = -100;
        int256 beforeOutputTokenDeltaB = 0;
        int256 afterInputTokenDeltaB = 0;
        int256 afterOutputTokenDeltaB = 0;
        uint256 bdvConverted = 100;
        uint256 overallCappedDeltaB = 50;
        address inputToken = beanEthWell;
        address outputToken = C.BEAN;

        uint256 penalty = LibConvert.calculateStalkPenalty(
            beforeOverallDeltaB,
            afterOverallDeltaB,
            beforeInputTokenDeltaB,
            beforeOutputTokenDeltaB,
            afterInputTokenDeltaB,
            afterOutputTokenDeltaB,
            bdvConverted,
            overallCappedDeltaB,
            inputToken,
            outputToken
        );
        assertEq(penalty, 50);
    }*/

    /*
    function testCalculateStalkPenaltyNoCappedDeltaB() public {
        int256 beforeDeltaB = 100;
        int256 afterDeltaB = 0;
        uint256 bdvRemoved = 100;
        uint256 cappedDeltaB = 0;
        uint256 penalty = LibConvert.calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvRemoved, cappedDeltaB);
        assertEq(penalty, 100);
    }

    function testCalculateStalkPenaltyNoCappedDeltaBNotZero() public {
        int256 beforeDeltaB = 101;
        int256 afterDeltaB = 1;
        uint256 bdvRemoved = 100;
        uint256 cappedDeltaB = 0;
        uint256 penalty = LibConvert.calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvRemoved, cappedDeltaB);
        assertEq(penalty, 100);
    }

    function testCalculateStalkPenaltyNoCappedDeltaBNotZeroHalf() public {
        int256 beforeDeltaB = 101;
        int256 afterDeltaB = 1;
        uint256 bdvRemoved = 100;
        uint256 cappedDeltaB = 50;
        uint256 penalty = LibConvert.calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvRemoved, cappedDeltaB);
        assertEq(penalty, 50);
    }

    function testCalculateStalkPenaltyNoCappedDeltaBToZeroHalf() public {
        int256 beforeDeltaB = 100;
        int256 afterDeltaB = 0;
        uint256 bdvRemoved = 100;
        uint256 cappedDeltaB = 50;
        uint256 penalty = LibConvert.calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvRemoved, cappedDeltaB);
        assertEq(penalty, 50);
    }

    function testCalculateStalkPenaltyLPtoLPSmallSlippage() public {
        int256 beforeDeltaB = 100;
        int256 afterDeltaB = 101;
        uint256 bdvRemoved = 100;
        uint256 cappedDeltaB = 100;
        uint256 penalty = LibConvert.calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvRemoved, cappedDeltaB);
        assertEq(penalty, 1);
    }

    function testCalculateStalkPenaltyLPtoLPLargeSlippageNoCapped() public {
        int256 beforeDeltaB = 100;
        int256 afterDeltaB = 151;
        uint256 bdvRemoved = 100;
        uint256 cappedDeltaB = 0;
        uint256 penalty = LibConvert.calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvRemoved, cappedDeltaB);
        assertEq(penalty, 51);
    }*/

    function testCalcStalkPenaltyUpToPeg() public {
        // make beanEthWell have negative deltaB so that it has convert capacity
        setDeltaBforWell(-1000e6, beanEthWell, C.WETH);
        (
            LibConvert.DeltaBStorage memory dbs,
            address inputToken,
            address outputToken,
            uint256 bdvConverted,
            uint256 overallConvertCapacity
        ) = setupTowardsPegDeltaBStorageNegative();

        (uint256 stalkPenaltyBdv, , , ) = LibConvert.calculateStalkPenalty(
            dbs,
            bdvConverted,
            overallConvertCapacity,
            inputToken,
            outputToken
        );
        assertEq(stalkPenaltyBdv, 0);
    }

    function testCalcStalkPenaltyDownToPeg() public {
        // make beanEthWell have positive deltaB so that it has convert capacity
        setDeltaBforWell(1000e6, beanEthWell, C.WETH);

        (
            LibConvert.DeltaBStorage memory dbs,
            address inputToken,
            address outputToken,
            uint256 bdvConverted,
            uint256 overallConvertCapacity
        ) = setupTowardsPegDeltaBStorageNegative();

        dbs.beforeInputTokenDeltaB = 100;
        dbs.beforeOutputTokenDeltaB = 100;

        (uint256 stalkPenaltyBdv, , , ) = LibConvert.calculateStalkPenalty(
            dbs,
            bdvConverted,
            overallConvertCapacity,
            inputToken,
            outputToken
        );
        assertEq(stalkPenaltyBdv, 0);
    }

    function testCalcStalkPenaltyNoOverallCap() public {
        (
            LibConvert.DeltaBStorage memory dbs,
            address inputToken,
            address outputToken,
            uint256 bdvConverted,
            uint256 overallConvertCapacity
        ) = setupTowardsPegDeltaBStorageNegative();

        overallConvertCapacity = 0;
        dbs.beforeOverallDeltaB = -100;

        (uint256 stalkPenaltyBdv, , , ) = LibConvert.calculateStalkPenalty(
            dbs,
            bdvConverted,
            overallConvertCapacity,
            inputToken,
            outputToken
        );
        assertEq(stalkPenaltyBdv, 100);
    }

    function testCalcStalkPenaltyNoInputTokenCap() public {
        (
            LibConvert.DeltaBStorage memory dbs,
            address inputToken,
            address outputToken,
            uint256 bdvConverted,
            uint256 overallConvertCapacity
        ) = setupTowardsPegDeltaBStorageNegative();

        dbs.beforeOverallDeltaB = -100;

        (uint256 stalkPenaltyBdv, , , ) = LibConvert.calculateStalkPenalty(
            dbs,
            bdvConverted,
            overallConvertCapacity,
            inputToken,
            outputToken
        );
        assertEq(stalkPenaltyBdv, 100);
    }

    function testCalcStalkPenaltyNoOutputTokenCap() public {
        (
            LibConvert.DeltaBStorage memory dbs,
            address inputToken,
            address outputToken,
            uint256 bdvConverted,
            uint256 overallConvertCapacity
        ) = setupTowardsPegDeltaBStorageNegative();

        inputToken = C.BEAN;
        outputToken = beanEthWell;
        dbs.beforeOverallDeltaB = -100;

        (uint256 stalkPenaltyBdv, , , ) = LibConvert.calculateStalkPenalty(
            dbs,
            bdvConverted,
            overallConvertCapacity,
            inputToken,
            outputToken
        );
        assertEq(stalkPenaltyBdv, 100);
    }

    ////// CONVERT TEST HELPERS //////

    function setupTowardsPegDeltaBStorageNegative()
        public
        view
        returns (
            LibConvert.DeltaBStorage memory dbs,
            address inputToken,
            address outputToken,
            uint256 bdvConverted,
            uint256 overallConvertCapacity
        )
    {
        dbs.beforeInputTokenDeltaB = -100;
        dbs.afterInputTokenDeltaB = 0;
        dbs.beforeOutputTokenDeltaB = -100;
        dbs.afterOutputTokenDeltaB = 0;
        dbs.beforeOverallDeltaB = 0;
        dbs.afterOverallDeltaB = 0;

        inputToken = beanEthWell;
        outputToken = C.BEAN;

        bdvConverted = 100;
        overallConvertCapacity = 100;
    }

    function mineBlockAndUpdatePumps() public {
        // mine a block so convert power is updated
        vm.roll(block.number + 1);
        updateMockPumpUsingWellReserves(beanEthWell);
        updateMockPumpUsingWellReserves(beanwstethWell);
    }

    function updateMockPumpUsingWellReserves(address well) public {
        Call[] memory pumps = IWell(well).pumps();
        for (uint i = 0; i < pumps.length; i++) {
            address pump = pumps[i].target;
            // pass to the pump the reserves that we actually have in the well
            uint[] memory reserves = IWell(well).getReserves();
            MockPump(pump).update(well, reserves, new bytes(0));

            console.log("updated reserves for pump: ", pump);
            console.log("well: ", well);
            console.log("reserves: ");
            for (uint j = 0; j < reserves.length; j++) {
                console.log("reserves[j]: ", reserves[j]);
            }
        }
    }

    function doBasicBeanToLP(uint256 amount, address user) public {
        int96 stem = depositBeanAndPassGermination(amount, user);
        beanToLPDoConvert(amount, stem, user);
    }

    function depositBeanAndPassGermination(
        uint256 amount,
        address user
    ) public returns (int96 stem) {
        vm.pauseGasMetering();
        // amount = bound(amount, 1e6, 5000e6);
        bean.mint(user, amount);

        // setup array of addresses with user
        address[] memory users = new address[](1);
        users[0] = user;

        (amount, stem) = setUpSiloDepositTest(amount, users);

        passGermination();
    }

    /**
     * @notice Deposits into Bean:ETH well and passes germination.
     * @param amount The amount of beans added to well, single-sided.
     */
    function depositLPAndPassGermination(
        uint256 amount
    ) public returns (int96 stem, uint256 lpAmountOut) {
        // mint beans to user 1
        bean.mint(users[1], amount);
        // user 1 deposits bean into bean:eth well, first approve
        vm.prank(users[1]);
        bean.approve(beanEthWell, type(uint256).max);

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = amount;
        tokenAmountsIn[1] = 0;

        vm.prank(users[1]);
        lpAmountOut = IWell(beanEthWell).addLiquidity(
            tokenAmountsIn,
            0,
            users[1],
            type(uint256).max
        );

        // approve spending well token to beanstalk
        vm.prank(users[1]);
        MockToken(beanEthWell).approve(BEANSTALK, type(uint256).max);

        vm.prank(users[1]);
        (, , stem) = silo.deposit(beanEthWell, lpAmountOut, LibTransfer.From.EXTERNAL);

        passGermination();
    }

    function beanToLPDoConvert(
        uint256 amount,
        int96 stem,
        address user
    ) public returns (int96 outputStem, uint256 outputAmount) {
        // do the convert

        // Create arrays for stem and amount. Tried just passing in [stem] and it's like nope.
        int96[] memory stems = new int96[](1);
        stems[0] = stem;

        AdvancedFarmCall[] memory beanToLPFarmCalls = createBeanToLPFarmCalls(
            amount,
            new AdvancedPipeCall[](0)
        );

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.resumeGasMetering();
        vm.prank(user); // do this as user 1
        (outputStem, outputAmount, , , ) = convert.pipelineConvert(
            C.BEAN, // input token
            stems, // stems
            amounts, // amount
            beanEthWell, // token out
            beanToLPFarmCalls // farmData
        );
    }

    function lpToBeanDoConvert(
        uint256 lpAmountOut,
        int96 stem,
        address user
    ) public returns (int96 outputStem, uint256 outputAmount) {
        // Create arrays for stem and amount. Tried just passing in [stem] and it's like nope.
        int96[] memory stems = new int96[](1);
        stems[0] = stem;

        AdvancedFarmCall[] memory beanToLPFarmCalls = createLPToBeanFarmCalls(lpAmountOut);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = lpAmountOut;

        vm.resumeGasMetering();
        vm.prank(user); // do this as user 1
        (outputStem, outputAmount, , , ) = convert.pipelineConvert(
            beanEthWell, // input token
            stems, // stems
            amounts, // amount
            C.BEAN, // token out
            beanToLPFarmCalls // farmData
        );
    }

    function getWellAmountOutForAddingBeans(uint256 amount) public view returns (uint256) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = 0;

        uint256 wellAmountOut = IWell(beanEthWell).getAddLiquidityOut(amounts);
        return wellAmountOut;
    }

    /**
     * Calculates LP out if Bean removed from one well and added to another.
     * @param amount Amount of LP token input
     * @param fromWell Well to pull liquidity from
     * @param toWell Well to add liquidity to
     */
    function getWellAmountOutFromLPtoLP(
        uint256 amount,
        address fromWell,
        address toWell
    ) public view returns (uint256) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = 0;

        uint256 wellRemovedBeans = IWell(fromWell).getRemoveLiquidityOneTokenOut(
            amount,
            IERC20(C.BEAN)
        );

        uint256[] memory addAmounts = new uint256[](2);
        addAmounts[0] = wellRemovedBeans;
        addAmounts[1] = 0;

        uint256 lpAmountOut = IWell(toWell).getAddLiquidityOut(addAmounts);
        return lpAmountOut;
    }

    function addEthToWell(address user, uint256 amount) public returns (uint256 lpAmountOut) {
        MockToken(C.WETH).mint(user, amount);

        vm.prank(user);
        MockToken(C.WETH).approve(beanEthWell, amount);

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = 0;
        tokenAmountsIn[1] = amount;

        vm.prank(user);
        lpAmountOut = IWell(beanEthWell).addLiquidity(tokenAmountsIn, 0, user, type(uint256).max);

        // approve spending well token to beanstalk
        vm.prank(user);
        MockToken(beanEthWell).approve(BEANSTALK, type(uint256).max);
    }

    function removeEthFromWell(address user, uint256 amount) public returns (uint256 lpAmountOut) {
        MockToken(C.WETH).mint(user, amount);

        vm.prank(user);
        MockToken(C.WETH).approve(beanEthWell, amount);

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = 0;
        tokenAmountsIn[1] = amount;

        vm.prank(user);
        lpAmountOut = IWell(beanEthWell).removeLiquidityOneToken(
            amount,
            IERC20(C.WETH),
            0,
            user,
            type(uint256).max
        );

        console.log("lpAmountOut: ", lpAmountOut);

        // approve spending well token to beanstalk
        vm.prank(user);
        MockToken(beanEthWell).approve(BEANSTALK, type(uint256).max);
    }

    /**
     * @notice Creates a pipeline calls for converting a bean to LP.
     * @param amountOfBean The amount of bean to convert.
     * @param extraPipeCalls Any additional pipe calls to add to the pipeline.
     */
    function createBeanToLPFarmCalls(
        uint256 amountOfBean,
        AdvancedPipeCall[] memory extraPipeCalls
    ) internal view returns (AdvancedFarmCall[] memory output) {
        // first setup the pipeline calls

        // setup approve max call
        bytes memory approveEncoded = abi.encodeWithSelector(
            IERC20.approve.selector,
            beanEthWell,
            MAX_UINT256
        );

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = amountOfBean;
        tokenAmountsIn[1] = 0;

        // encode Add liqudity.
        bytes memory addLiquidityEncoded = abi.encodeWithSelector(
            IWell.addLiquidity.selector,
            tokenAmountsIn, // tokenAmountsIn
            0, // min out
            C.PIPELINE, // recipient
            type(uint256).max // deadline
        );

        // Fabricate advancePipes:
        AdvancedPipeCall[] memory advancedPipeCalls = new AdvancedPipeCall[](100);

        uint256 i = 0;

        // Action 0: approve the Bean-Eth well to spend pipeline's bean.
        advancedPipeCalls[i++] = AdvancedPipeCall(
            C.BEAN, // target
            approveEncoded, // calldata
            abi.encode(0) // clipboard
        );

        // Action 2: Add One sided Liquidity into the well.
        advancedPipeCalls[i++] = AdvancedPipeCall(
            beanEthWell, // target
            addLiquidityEncoded, // calldata
            abi.encode(0) // clipboard
        );

        // append any extra pipe calls
        for (uint j; j < extraPipeCalls.length; j++) {
            advancedPipeCalls[i++] = extraPipeCalls[j];
        }

        assembly {
            mstore(advancedPipeCalls, i)
        }

        // Encode into a AdvancedFarmCall. NOTE: advancedFarmCall != advancedPipeCall.
        // AdvancedFarmCall calls any function on the beanstalk diamond.
        // advancedPipe is one of the functions that its calling.
        // AdvancedFarmCall cannot call approve/addLiquidity, but can call AdvancedPipe.
        // AdvancedPipe can call any arbitrary function.
        AdvancedFarmCall[] memory advancedFarmCalls = new AdvancedFarmCall[](1);

        bytes memory advancedPipeCalldata = abi.encodeWithSelector(
            depot.advancedPipe.selector,
            advancedPipeCalls,
            0
        );

        advancedFarmCalls[0] = AdvancedFarmCall(advancedPipeCalldata, new bytes(0));
        return advancedFarmCalls;
    }

    function createAdvancedFarmCallsFromAdvancedPipeCalls(
        AdvancedPipeCall[] memory advancedPipeCalls
    ) private view returns (AdvancedFarmCall[] memory) {
        AdvancedFarmCall[] memory advancedFarmCalls = new AdvancedFarmCall[](1);
        bytes memory advancedPipeCalldata = abi.encodeWithSelector(
            depot.advancedPipe.selector,
            advancedPipeCalls,
            0
        );

        advancedFarmCalls[0] = AdvancedFarmCall(advancedPipeCalldata, new bytes(0));
        return advancedFarmCalls;
    }

    function createLPToBeanFarmCalls(
        uint256 amountOfLP
    ) private view returns (AdvancedFarmCall[] memory output) {
        console.log("createLPToBean amountOfLP: ", amountOfLP);
        // first setup the pipeline calls

        // setup approve max call
        bytes memory approveEncoded = abi.encodeWithSelector(
            IERC20.approve.selector,
            beanEthWell,
            MAX_UINT256
        );

        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = amountOfLP;
        tokenAmountsIn[1] = 0;

        // encode remove liqudity.
        bytes memory removeLiquidityEncoded = abi.encodeWithSelector(
            IWell.removeLiquidityOneToken.selector,
            amountOfLP, // tokenAmountsIn
            C.BEAN, // tokenOut
            0, // min out
            C.PIPELINE, // recipient
            type(uint256).max // deadline
        );

        // Fabricate advancePipes:
        AdvancedPipeCall[] memory advancedPipeCalls = new AdvancedPipeCall[](2);

        // Action 0: approve the Bean-Eth well to spend pipeline's bean.
        advancedPipeCalls[0] = AdvancedPipeCall(
            C.BEAN, // target
            approveEncoded, // calldata
            abi.encode(0) // clipboard
        );

        // Action 2: Remove One sided Liquidity into the well.
        advancedPipeCalls[1] = AdvancedPipeCall(
            beanEthWell, // target
            removeLiquidityEncoded, // calldata
            abi.encode(0) // clipboard
        );

        // Encode into a AdvancedFarmCall. NOTE: advancedFarmCall != advancedPipeCall.

        // AdvancedFarmCall calls any function on the beanstalk diamond.
        // advancedPipe is one of the functions that its calling.
        // AdvancedFarmCall cannot call approve/addLiquidity, but can call AdvancedPipe.
        // AdvancedPipe can call any arbitrary function.
        AdvancedFarmCall[] memory advancedFarmCalls = new AdvancedFarmCall[](1);

        bytes memory advancedPipeCalldata = abi.encodeWithSelector(
            depot.advancedPipe.selector,
            advancedPipeCalls,
            0
        );

        advancedFarmCalls[0] = AdvancedFarmCall(advancedPipeCalldata, new bytes(0));

        // encode into bytes.
        // output = abi.encode(advancedFarmCalls);
        return advancedFarmCalls;
    }

    function createLPToLPFarmCalls(
        uint256 amountOfLP,
        address well
    ) private returns (AdvancedFarmCall[] memory output) {
        console.log("createLPToBean amountOfLP: ", amountOfLP);

        // setup approve max call
        bytes memory approveEncoded = abi.encodeWithSelector(
            IERC20.approve.selector,
            beanwstethWell,
            MAX_UINT256
        );

        // encode remove liqudity.
        bytes memory removeLiquidityEncoded = abi.encodeWithSelector(
            IWell.removeLiquidityOneToken.selector,
            amountOfLP, // lpAmountIn
            C.BEAN, // tokenOut
            0, // min out
            C.PIPELINE, // recipient
            type(uint256).max // deadline
        );

        uint256[] memory emptyAmountsIn = new uint256[](2);

        // encode add liquidity
        bytes memory addLiquidityEncoded = abi.encodeWithSelector(
            IWell.addLiquidity.selector,
            emptyAmountsIn, // to be pasted in
            0, // min out
            C.PIPELINE, // recipient
            type(uint256).max // deadline
        );

        // Fabricate advancePipes:
        AdvancedPipeCall[] memory advancedPipeCalls = new AdvancedPipeCall[](3);

        // Action 0: approve the Bean-Eth well to spend pipeline's bean.
        advancedPipeCalls[0] = AdvancedPipeCall(
            C.BEAN, // target
            approveEncoded, // calldata
            abi.encode(0) // clipboard
        );

        // Action 1: remove beans from well.
        advancedPipeCalls[1] = AdvancedPipeCall(
            well, // target
            removeLiquidityEncoded, // calldata
            abi.encode(0) // clipboard
        );

        // returnDataItemIndex, copyIndex, pasteIndex
        bytes memory clipboard = abi.encodePacked(
            bytes2(0x0100), // clipboard type 1
            uint80(1), // from result of call at index 1
            uint80(32), // take the first param
            uint80(196) // paste into the 6th 32 bytes of the clipboard
        );

        // Action 2: add beans to wsteth:bean well.
        advancedPipeCalls[2] = AdvancedPipeCall(
            beanwstethWell, // target
            addLiquidityEncoded, // calldata
            clipboard
        );

        // Encode into a AdvancedFarmCall. NOTE: advancedFarmCall != advancedPipeCall.

        // AdvancedFarmCall calls any function on the beanstalk diamond.
        // advancedPipe is one of the functions that its calling.
        // AdvancedFarmCall cannot call approve/addLiquidity, but can call AdvancedPipe.
        // AdvancedPipe can call any arbitrary function.
        AdvancedFarmCall[] memory advancedFarmCalls = new AdvancedFarmCall[](1);

        bytes memory advancedPipeCalldata = abi.encodeWithSelector(
            depot.advancedPipe.selector,
            advancedPipeCalls,
            0
        );

        advancedFarmCalls[0] = AdvancedFarmCall(advancedPipeCalldata, new bytes(0));

        // encode into bytes.
        // output = abi.encode(advancedFarmCalls);
        return advancedFarmCalls;
    }

    function calculateDeltaBForWellAfterSwapFromLP(
        uint256 amountIn,
        address well
    ) public view returns (int256 deltaB, uint256 beansOut) {
        // calculate new reserves for well using get swap out and manually figure out what deltaB would be

        // get reserves before swap
        uint256[] memory reserves = IWell(well).getReserves();

        beansOut = IWell(well).getRemoveLiquidityOneTokenOut(amountIn, IERC20(C.BEAN));

        // get index of bean token
        uint256 beanIndex = LibWell.getBeanIndex(IWell(well).tokens());
        (address nonBeanToken, uint256 nonBeanIndex) = LibWell.getNonBeanTokenAndIndexFromWell(
            well
        );

        // remove beanOut from reserves bean index
        reserves[beanIndex] = reserves[beanIndex].sub(beansOut);
        reserves[nonBeanIndex] = reserves[nonBeanIndex].add(amountIn);

        // get new deltaB
        deltaB = LibWellMinting.calculateDeltaBFromReserves(well, reserves, 0);
        console.log("deltaB: ");
        console.logInt(deltaB);
    }

    function calculateDeltaBForWellAfterSwapFromBean(
        uint256 beansIn,
        address well
    ) public view returns (int256 deltaB, uint256 lpOut) {
        // get reserves before swap
        uint256[] memory reserves = IWell(well).getReserves();

        // get index of bean token
        uint256 beanIndex = LibWell.getBeanIndex(IWell(well).tokens());
        (address nonBeanToken, uint256 nonBeanIndex) = LibWell.getNonBeanTokenAndIndexFromWell(
            well
        );
        uint256[] memory tokenAmountsIn = new uint256[](2);
        tokenAmountsIn[0] = beansIn;
        tokenAmountsIn[1] = 0;
        lpOut = IWell(well).getAddLiquidityOut(tokenAmountsIn);

        console.log("beanIndex: ");
        console.log(beanIndex);
        console.log("nonBeanIndex: ");
        console.log(nonBeanIndex);

        console.log("reserve0: ");
        console.log(reserves[0]);
        console.log("reserve1: ");
        console.log(reserves[1]);

        console.log("lpOut: ");
        console.log(lpOut);
        console.log("beansIn: ");
        console.log(beansIn);

        // add to bean index (no beans out on this one)
        reserves[beanIndex] = reserves[beanIndex].add(beansIn);

        console.log("updated reserve0: ");
        console.log(reserves[0]);
        console.log("updated reserve1: ");
        console.log(reserves[1]);

        // get new deltaB
        deltaB = LibWellMinting.calculateDeltaBFromReserves(well, reserves, 0);
        console.log("deltaB: ");
        console.logInt(deltaB);
    }
}
