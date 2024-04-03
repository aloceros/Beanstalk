/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import {C} from "contracts/C.sol";
import {LibTractor} from "contracts/libraries/LibTractor.sol";
import {LibSilo} from "contracts/libraries/Silo/LibSilo.sol";
import {LibTokenSilo} from "contracts/libraries/Silo/LibTokenSilo.sol";
import {LibSafeMath32} from "contracts/libraries/LibSafeMath32.sol";
import {ReentrancyGuard} from "../ReentrancyGuard.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibConvert} from "contracts/libraries/Convert/LibConvert.sol";
import {AppStorage, LibAppStorage} from "contracts/libraries/LibAppStorage.sol";
import {AdvancedFarmCall, LibFarm} from "../../libraries/LibFarm.sol";
import {LibWellMinting} from "../../libraries/Minting/LibWellMinting.sol";
import {IPipeline, PipeCall} from "contracts/interfaces/IPipeline.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {LibFunction} from "contracts/libraries/LibFunction.sol";

import "forge-std/console.sol";

interface IBeanstalk {
    function bdv(address token, uint256 amount) external view returns (uint256);
    function poolDeltaB(address pool) external view returns (int256);
}
import {LibGerminate} from "contracts/libraries/Silo/LibGerminate.sol";



/**
 * @author Publius, Brean, DeadManWalking, pizzaman1337, funderberker
 * @title ConvertFacet handles converting Deposited assets within the Silo.
 **/
contract ConvertFacet is ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using LibSafeMath32 for uint32;
    address internal constant PIPELINE = 0xb1bE0000C6B3C62749b5F0c92480146452D15423; //import this from C.sol?
    IBeanstalk private constant BEANSTALK = IBeanstalk(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);

    event Convert(
        address indexed account,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    );

    event RemoveDeposit(
        address indexed account,
        address indexed token,
        int96 stem,
        uint256 amount,
        uint256 bdv
    );

    event RemoveDeposits(
        address indexed account,
        address indexed token,
        int96[] stems,
        uint256[] amounts,
        uint256 amount,
        uint256[] bdvs
    );


    struct AssetsRemovedConvert {
        LibSilo.Removed active;
        uint256 tokensRemoved;
        // uint256 stalkRemoved;
        // uint256 bdvRemoved;
        uint256[] bdvsRemoved;
        uint256[] stalksRemoved;
        uint256[] depositIds;
    }

    struct MultiCrateDepositData {
        uint256 amountPerBdv;
        uint256 totalAmount;
        uint256 crateAmount;
        uint256 depositedBdv;
    }

    struct PipelineConvertData {
        uint256[] bdvsRemoved;
        uint256[] grownStalks;
        int256 startingDeltaB;
        uint256 amountOut;
        uint256 percentStalkPenalty; // 0 means no penalty, 1 means 100% penalty
    }

    // TODO: when we updated to Solidity 0.8, use the native abs function
    // the verson of OpenZeppelin we're on does not support abs
    function abs(int256 a) internal pure returns (uint256) {
        return a >= 0 ? uint256(a) : uint256(-a);
    }

    /**
     * @notice convert allows a user to convert a deposit to another deposit,
     * given that the conversion is supported by the ConvertFacet.
     * For example, a user can convert LP into Bean, only when beanstalk is below peg, 
     * or convert beans into LP, only when beanstalk is above peg.
     * @param convertData  input parameters to determine the conversion type.
     * @param stems the stems of the deposits to convert 
     * @param amounts the amounts within each deposit to convert
     * @return toStem the new stems of the converted deposit
     * @return fromAmount the amount of tokens converted from
     * @return toAmount the amount of tokens converted to
     * @return fromBdv the bdv of the deposits converted from
     * @return toBdv the bdv of the deposit converted to
     */
    function convert(
        bytes calldata convertData,
        int96[] memory stems,
        uint256[] memory amounts
    )
        external
        payable
        nonReentrant
        returns (int96 toStem, uint256 fromAmount, uint256 toAmount, uint256 fromBdv, uint256 toBdv)
    {
        LibTractor._setPublisher(msg.sender);

        address toToken; address fromToken; uint256 grownStalk;
        (toToken, fromToken, toAmount, fromAmount) = LibConvert.convert(convertData);

        require(fromAmount > 0, "Convert: From amount is 0.");

        LibSilo._mow(LibTractor._getUser(), fromToken);
        LibSilo._mow(LibTractor._getUser(), toToken);

        (grownStalk, fromBdv, ,) = _withdrawTokens(
            fromToken,
            stems,
            amounts,
            fromAmount
        );

        uint256 newBdv = LibTokenSilo.beanDenominatedValue(toToken, toAmount);
        toBdv = newBdv > fromBdv ? newBdv : fromBdv;

        toStem = _depositTokensForConvert(toToken, toAmount, toBdv, grownStalk);

        emit Convert(LibTractor._getUser(), fromToken, toToken, fromAmount, toAmount);

        LibTractor._resetPublisher();
    }


    /**
     * A farm convert needs to be able to take in:
     * 1. A list of tokens, stems, and amounts for input
     * 2. An output token address
     * 3. A farm function that does a swap, somehow we have to pass all the input tokens and amounts to this function
     * 
     * I was considering adding an allowConvertPastPeg bool, which if false, would revert the txn.
     * This functionality can be achieve by baking it into the pipeline calls however.
     * 
     * It is assumed you pass in stems/amounts in order from highest grown stalk per bdv to lowest.
     * Whatever the case, if you convert past peg, you'll lose the stalk starting from the end crates.
     */

    function pipelineConvert(
        address inputToken,
        int96[] calldata stems, //array of stems to convert
        uint256[] calldata amounts, //amount from each crate to convert
        address outputToken,
        AdvancedFarmCall[] calldata farmCalls
    )
        external
        payable
        nonReentrant
    {   
        LibTractor._setPublisher(msg.sender);


        // mow input and output tokens: 
        LibSilo._mow(LibTractor._getUser(), inputToken);
        LibSilo._mow(LibTractor._getUser(), outputToken);

        
        // AppStorage storage s = LibAppStorage.diamondStorage();

        // require(s.ss[outputToken].milestoneSeason != 0, "Token not whitelisted");


        //pull out the deposits for each stem so we can get total amount
        //all the crates passed to this function will be combined into one,
        //so if a user wants to do special combining of crates, this function can be called multiple times

        
        uint256 maxTokens = 0;
        for (uint256 i = 0; i < stems.length; i++) {
            maxTokens = maxTokens.add(amounts[i]);
        }


        PipelineConvertData memory pipeData;

        ( , , pipeData.bdvsRemoved, pipeData.grownStalks) = _withdrawTokens(
            inputToken,
            stems,
            amounts,
            maxTokens
        );

        // storePoolDeltaB(inputToken, outputToken);
        pipeData.startingDeltaB = getCombinedDeltaBForTokens(inputToken, outputToken);
        console.log('startingDeltaB:');
        console.logInt(pipeData.startingDeltaB);


        IERC20(inputToken).transfer(PIPELINE, maxTokens);
        pipeData.amountOut = executeAdvancedFarmCalls(farmCalls);

        console.log('amountOut after pipe calls: ', pipeData.amountOut);
        
        //user MUST leave final assets in pipeline, allowing us to verify that the farm has been called successfully.
        //this also let's us know how many assets to attempt to pull out of the final type
        transferTokensFromPipeline(outputToken, pipeData.amountOut);


        //note bdv could decrease here, by a lot, esp because you can deposit only a fraction
        //of what you withdrew


        //stalk bonus/penalty will be applied here

        // pipeData.changeInDeltaB = getCombinedDeltaBForTokens(inputToken, outputToken).sub(pipeData.changeInDeltaB);
        // console.log('after changeInDeltaB:');
        // console.logInt(pipeData.changeInDeltaB);

        int256 cappedDeltaB;
        (cappedDeltaB, , ) = LibWellMinting.cappedReservesDeltaB(inputToken);

        uint256 stalkPenaltyBdv = _calculateStalkPenalty(pipeData.startingDeltaB, getCombinedDeltaBForTokens(inputToken, outputToken), pipeData.bdvsRemoved, abs(cappedDeltaB));
        console.log('stalkPenaltyBdv: ', stalkPenaltyBdv);
        pipeData.grownStalks = _applyPenaltyToGrownStalks(stalkPenaltyBdv, pipeData.bdvsRemoved, pipeData.grownStalks);

        // Convert event emitted within this function
        _depositTokensForConvertMultiCrate(inputToken, outputToken, pipeData.amountOut, pipeData.bdvsRemoved, pipeData.grownStalks, amounts, stalkPenaltyBdv);


        //there's nothing about total BDV in this event, but it can be derived from the AddDeposit events
        LibTractor._resetPublisher();
    }

    function applyPenaltyToGrownStalks(uint256 penaltyBdv, uint256[] memory bdvsRemoved, uint256[] memory grownStalks) external view returns (uint256[] memory) {
        return _applyPenaltyToGrownStalks(penaltyBdv, bdvsRemoved, grownStalks);
    }

    function _applyPenaltyToGrownStalks(uint256 stalkPenaltyBdv, uint256[] memory bdvsRemoved, uint256[] memory grownStalks)
        internal view returns (uint256[] memory) {

        for (uint256 i = bdvsRemoved.length-1; i >= 0; i--) {
            uint256 bdvRemoved = bdvsRemoved[i];
            uint256 grownStalk = grownStalks[i];

            if (stalkPenaltyBdv >= bdvRemoved) {
                stalkPenaltyBdv -= bdvRemoved;
                grownStalks[i] = 0;
            } else {
                uint256 penaltyPercentage = stalkPenaltyBdv.mul(1e16).div(bdvRemoved);
                grownStalks[i] = grownStalk.sub(grownStalk.mul(penaltyPercentage).div(1e16));
                stalkPenaltyBdv = 0;
            }
            if (stalkPenaltyBdv == 0) {
                break;
            }
        }
        return grownStalks;
    }

    function calculateStalkPenalty(int256 beforeDeltaB, int256 afterDeltaB, uint256[] memory bdvsRemoved, uint256 cappedDeltaB) external returns (uint256) {
        return _calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvsRemoved, cappedDeltaB);
    }

    /**
     * @notice Calculates the percentStalkPenalty for a given convert.
     * @dev The percentStalkPenalty is the amount of Stalk that is lost as a result of converting against
     * or past peg.
     * @param beforeDeltaB The deltaB before the deposit.
     * @param afterDeltaB The deltaB after the deposit.
     * @param bdvsRemoved The amount of BDVs that were removed, will be summed in this function.
     * @return percentStalkPenalty The percent of stalk that should be lost, 0 means no penalty, 1 means 100% penalty.
     * 
     * TODO: External only so that tests can be written on it. Any danger in leaving it public? It's just a pure function so I don't think so.
     */

    // TODO change to pure upon log removal
    function _calculateStalkPenalty(int256 beforeDeltaB, int256 afterDeltaB, uint256[] memory bdvsRemoved, uint256 cappedDeltaB) internal returns (uint256) {

        uint256 bdvConverted;
        for (uint256 i = 0; i < bdvsRemoved.length; i++) {
            bdvConverted = bdvConverted.add(bdvsRemoved[i]);
        }

        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 crossoverAmount = 0;


        console.log('beforeDeltaB: ');
        console.logInt(beforeDeltaB);
        console.log('afterDeltaB: ');
        console.logInt(afterDeltaB);
        console.log('bdvConverted: ', bdvConverted);

        // Check if the signs of beforeDeltaB and afterDeltaB are different,
        // indicating that deltaB has crossed zero
        // if (beforeDeltaB.mul(afterDeltaB) < 0) {
        // The bitwise XOR of two signed integers will be positive if they have different signs, and negative if they have the same sign
        // Maybe not use XOR if there's some obscure uninteded behavior?
        if ((beforeDeltaB ^ afterDeltaB) < 0 || beforeDeltaB == 0 || afterDeltaB == 0) {

            if (beforeDeltaB == 0 && afterDeltaB != 0) {
                //this means we converted away from peg, so entire amount of bdvConverted is penalty
                return bdvConverted;
            }

            if (afterDeltaB == 0) {
                return 0; //perfectly to peg, all good
            }



            // Calculate how far past peg we went - so actually this is just abs of new deltaB
            crossoverAmount = uint256(abs(int256(afterDeltaB)));

            console.log('crossoverAmount: ', crossoverAmount);

            // Check if the crossoverAmount is greater than or equal to bdvConverted
            // TODO: see if we can find cases where bdcConverted doesn't match the deltaB diff? should always in theory afaict
            if (crossoverAmount > bdvConverted) {
                // If the entire bdvConverted amount crossed over, something is fishy, bdv amounts wrong?
                revert("Convert: converted farther than bdv");
                // return 1e18; // 1e18 represents 100% as a fixed-point number with 18 decimal places
                // TODO: consider if this is a good amount of precision
            } else {
                // return amount crossed over
                return crossoverAmount;
            }
        } else if (beforeDeltaB <= 0 && afterDeltaB < beforeDeltaB) { 
            return bdvConverted; // actually penalty should be amount against peg you went?
        } else if (beforeDeltaB >= 0 && afterDeltaB > beforeDeltaB) { 
            return bdvConverted; // actually penalty should be amount against peg you went?
        }

        // at this point we are converting in direction of peg, but we may have gone past it
        // calculate how much closer

        // see if convert power for this block has been setup yet
        if (s.convertPowerThisBlock[block.number].hasConvertHappenedThisBlock == false) {
            // setup initial available convert power for this block at the current deltaB
            // use insta deltaB that's from previous block
            
            s.convertPowerThisBlock[block.number].convertPower = cappedDeltaB;
            s.convertPowerThisBlock[block.number].hasConvertHappenedThisBlock = true;
        }

        // calculate how much deltaB convert is happening with this convert
        uint256 convertAmountInDirectionOfPeg = abs(beforeDeltaB - afterDeltaB);

        if (convertAmountInDirectionOfPeg <= s.convertPowerThisBlock[block.number].convertPower) {
            // all good, you're using less than the available convert power

            // subtract from convert power available for this block
            s.convertPowerThisBlock[block.number].convertPower -= convertAmountInDirectionOfPeg;

            return crossoverAmount;
        } else {
            // you're using more than the available convert power

            // penalty will be how far past peg you went
            uint256 penalty = convertAmountInDirectionOfPeg - s.convertPowerThisBlock[block.number].convertPower;

            // all convert power for this block is used up
            s.convertPowerThisBlock[block.number].convertPower = 0;

            return penalty+crossoverAmount; // should this be capped at bdvConverted?
        }


    // If the deltaB did not cross zero, or is the same before/after, return 0. In the future maybe calculate bonus here.
    return 0;
}

    //for finding the before/after deltaB difference, we need to use the min of
    //the inst and the twa deltaB

    //note we need a way to get insta version of this
    function getCombinedDeltaBForTokens(address inputToken, address outputToken) internal view
        returns (int256 combinedDeltaBinsta) {
        //get deltaB of input/output tokens for comparison later
        // combinedDeltaBtwa = getDeltaBIfNotBeanInsta(inputToken) + getDeltaBIfNotBeanInsta(outputToken);
        combinedDeltaBinsta = getDeltaBIfNotBeanInsta(inputToken).add(getDeltaBIfNotBeanInsta(outputToken));
        console.log('combinedDeltaBinsta:');
        console.logInt(combinedDeltaBinsta);
    }

    function getDeltaBIfNotBeanInsta(address token) internal view returns (int256 instDeltaB) {
        console.log('getDeltaBIfNotBean token: ', token);
        if (token == address(C.bean())) {
            return 0;
        }
        instDeltaB = LibWellMinting.instantaneousDeltaBForConvert(token);
        console.log('instDeltaB: ');
        console.logInt(instDeltaB);
        return instDeltaB;
    }

    function logResultBySlot(bytes memory data) public view returns (bytes[] memory args) {
        // Extract the selector

        
        // assembly {
        //     selector := mload(add(data, 32))
        // }


        // selector = bytes4(uint32(uint256(data[0])));

        // console.log('init array');
        
        // Initialize an array to hold the arguments
        args = new bytes[]((data.length) / 32);

        // console.log('extract args');
        
        // Extract each argument
        for (uint i = 0; i < data.length; i += 32) {
            // console.log('here');
            bytes memory arg = new bytes(32);
            for (uint j = 0; j < 32; j++) {
                // console.log('here 2');
                // Check if we're within the bounds of the data array
                if (i + j < data.length) {
                    // console.log('good length');
                    arg[j] = data[i + j];
                } else {
                    console.log('bad length');
                    // If we're out of bounds, fill the rest of the argument with zeros
                    arg[j] = byte(0);
                    console.log('hm we went out of bounds uh oh');
                }
            }
            // console.log('here 3');
            
            uint index = i / 32;
            // Check if the index is within bounds
            if (index < args.length) {
                args[index] = arg;
            } else {
                console.log('index was out of bounds');
                console.log('index: ', index);
                console.log('args.length: ', args.length);
                // Handle the case where the index is out of bounds
                // This should not happen if the calculation is correct, but it's good to have a safeguard
                // revert("Index out of bounds");
            }
        }
        
        // Print the selector
        // console.log('extractData printing selector');
        // console.logBytes4(selector);

        console.log('print cargs');
        
        // Print each argument
        for (uint i = 0; i < args.length; i++) {
            console.log('logResultBySlot printing slot: ');
            console.logBytes(args[i]);
        }
    }

    function executeAdvancedFarmCalls(AdvancedFarmCall[] calldata calls)
        internal
        returns (
            uint256 amountOut
        )
    {
        console.log("executeAdvancedFarmCalls:");
        // console.log("bytes being fed in:");
        // console.logBytes(calls);
        // bytes memory lastBytes = results[results.length - 1];
        //at this point lastBytes is 3 slots long, we just need the last slot (first two slots contain 0x2 for some reason)
        bytes[] memory results;
        // AdvancedFarmCall[] memory calls = abi.decode(calls, (AdvancedFarmCall[]));
        // console.log("advancedFarm decoded.");

        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            // console.log("looping:", i);
            // console.log("calldata:");
            // console.logBytes(calls[i].callData);
            require(calls[i].callData.length != 0, "Convert: empty AdvancedFarmCall");
            results[i] = LibFarm._advancedFarmMem(calls[i], results);
        }

        // assume last value is the amountOut
        // todo: for full functionality, we should instead have the user specify the index of the amountOut
        // in the farmCallResult.
        // amountOut = abi.decode(LibBytes.sliceFrom(results[results.length-1], 64), (uint256));

        // grab very last 32 bytes
        amountOut = abi.decode(LibBytes.sliceFrom(results[results.length-1], results[results.length-1].length-32), (uint256));
        console.log('executeAdvancedFarmCalls amountOut: ', amountOut);
    }


    function transferTokensFromPipeline(address tokenOut, uint256 userReturnedConvertValue) private {
        // todo investigate not using the entire interface but just using the function selector here
        PipeCall memory p;
        p.target = address(tokenOut); //contract that pipeline will call
        p.data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(this),
            userReturnedConvertValue
        );

        //todo: see if we can find a way to spit out a custom error saying it failed here, rather than a generic ERC20 revert
        // bool success;
        // bytes memory result;
        // (success, result) = p.target.staticcall(p.data);
        // if (!success) {
        //     revert("Failed to transfer tokens from pipeline");
        // }
        //I don't think calling checkReturn here is necessary if success is false?
        // LibFunction.checkReturn(success, result);

        IPipeline(PIPELINE).pipe(p);
    }

    // todo: implement oracle
    function getOracleprice() internal returns (uint256) {
        return 1e6;
    }

    function _bdv(address token, uint256 amount) internal returns (uint256) {
        return LibTokenSilo.beanDenominatedValue(token, amount);
    }

    /**
     * @notice removes the deposits from msg.sender and returns the
     * grown stalk and bdv removed.
     * 
     * @dev if a user inputs a stem of a deposit that is `germinating`, 
     * the function will omit that deposit. This is due to the fact that
     * germinating deposits can be manipulated and skip the germination process.
     */
    function _withdrawTokens(
        address token,
        int96[] memory stems,
        uint256[] memory amounts,
        uint256 maxTokens
    ) internal returns (uint256, uint256, uint256[] memory bdvs, uint256[] memory stalksRemoved) {
        require(
            stems.length == amounts.length,
            "Convert: stems, amounts are diff lengths."
        );
        // LibSilo.AssetsRemoved memory a;
        AssetsRemovedConvert memory a;
        uint256 i = 0;

        // a bracket is included here to avoid the "stack too deep" error.
        {
            a.bdvsRemoved = new uint256[](stems.length);
            a.stalksRemoved = new uint256[](stems.length);
            a.depositIds = new uint256[](stems.length);

            // get germinating stem and stemTip for the token
            LibGerminate.GermStem memory germStem = LibGerminate.getGerminatingStem(token);

            while ((i < stems.length) && (a.active.tokens < maxTokens)) {

                console.log('_withdrawTokens i: ', i);
                console.log('_withdrawTokens amounts[i]', amounts[i]);

                // skip any stems that are germinating, due to the ability to 
                // circumvent the germination process.
                if (germStem.germinatingStem <= stems[i]) {
                    i++;
                    console.log('this stuff was still germinating');
                    continue;
                }

                console.log('_withdrawTokens stems[i]: ');
                console.logInt(stems[i]);

                if (a.active.tokens.add(amounts[i]) >= maxTokens) amounts[i] = maxTokens.sub(a.active.tokens);

                console.log('doing remove deposit from account');
                
                a.bdvsRemoved[i] = LibTokenSilo.removeDepositFromAccount(
                        LibTractor._getUser(),
                        token,
                        stems[i],
                        amounts[i]
                    );
                
                a.stalksRemoved[i] = LibSilo.stalkReward(
                        stems[i],
                        germStem.stemTip,
                        a.bdvsRemoved[i].toUint128()
                    );
                a.active.stalk = a.active.stalk.add(a.stalksRemoved[i]);
                
                console.log('a.active.stalk: ', a.active.stalk);
                a.active.tokens = a.active.tokens.add(amounts[i]);
                console.log('a.active.tokens: ', a.active.tokens);
                a.active.bdv = a.active.bdv.add(a.bdvsRemoved[i]);
                console.log('a.active.bdv: ', a.active.bdv);
                
                a.depositIds[i] = uint256(LibBytes.packAddressAndStem(
                    token,
                    stems[i]
                ));
                i++;
            }
            for (i; i < stems.length; ++i) amounts[i] = 0;
            
            emit RemoveDeposits(
                LibTractor._getUser(),
                token,
                stems,
                amounts,
                a.active.tokens,
                a.bdvsRemoved
            );

            emit LibSilo.TransferBatch(
                LibTractor._getUser(), 
                LibTractor._getUser(),
                address(0), 
                a.depositIds, 
                amounts
            );
        }

        console.log('maxTokens: ', maxTokens);
        console.log('a.active.tokens: ', a.active.tokens);
        console.log('a.active.stalk: ', a.active.stalk);
        console.log('stalk from issued: ', a.active.bdv.mul(s.ss[token].stalkIssuedPerBdv));
        console.log('total burn: ', a.active.stalk.add(a.active.bdv.mul(s.ss[token].stalkIssuedPerBdv)));

        require(
            a.active.tokens == maxTokens,
            "Convert: Not enough tokens removed."
        );
        LibTokenSilo.decrementTotalDeposited(token, a.active.tokens, a.active.bdv);

        console.log('burning active stalk');

        // all deposits converted are not germinating.
        LibSilo.burnActiveStalk(
            LibTractor._getUser(),
            a.active.stalk.add(a.active.bdv.mul(s.ss[token].stalkIssuedPerBdv))
        );
        return (a.active.stalk, a.active.bdv, a.bdvsRemoved, a.stalksRemoved);
    }


    function _depositTokensForConvert(
        address token,
        uint256 amount,
        uint256 bdv,
        uint256 grownStalk
    ) internal returns (int96 stem) {
        require(bdv > 0 && amount > 0, "Convert: BDV or amount is 0.");
        
        LibGerminate.Germinate germ;

        // calculate the stem and germination state for the new deposit.
        (stem, germ) = LibTokenSilo.calculateStemForTokenFromGrownStalk(token, grownStalk, bdv);
        
        // increment totals based on germination state, 
        // as well as issue stalk to the user.
        // if the deposit is germinating, only the inital stalk of the deposit is germinating. 
        // the rest is active stalk.
        if (germ == LibGerminate.Germinate.NOT_GERMINATING) {
            LibTokenSilo.incrementTotalDeposited(token, amount, bdv);
            LibSilo.mintActiveStalk(
                LibTractor._getUser(), 
                bdv.mul(LibTokenSilo.stalkIssuedPerBdv(token)).add(grownStalk)
            );
        } else {
            LibTokenSilo.incrementTotalGerminating(token, amount, bdv, germ);
            // safeCast not needed as stalk is <= max(uint128)
            LibSilo.mintGerminatingStalk(LibTractor._getUser(), uint128(bdv.mul(LibTokenSilo.stalkIssuedPerBdv(token))), germ);   
            LibSilo.mintActiveStalk(LibTractor._getUser(), grownStalk);
        }
        LibTokenSilo.addDepositToAccount(
            LibTractor._getUser(),
            token, 
            stem, 
            amount,
            bdv,
            LibTokenSilo.Transfer.emitTransferSingle
        );        
    }

    /**
     * @dev Add this amount of tokens to the silo, splitting the deposits by bdv into multiple crates.
     * @param inputToken The input token for the convert.
     * @param outputToken The output token for the convert.
     * @param amount The amount of tokens to deposit.
     * @param bdvs The bdvs to split the amounts into
     * @param grownStalks The amount of Stalk to deposit per crate
     * @param inputAmounts The amount of tokens to deposit per crate
     * @param stalkPenaltyBdv The BDV amount that gets penalized
     */
    function _depositTokensForConvertMultiCrate(
        address inputToken,
        address outputToken,
        uint256 amount,
        uint256[] memory bdvs,
        uint256[] memory grownStalks,
        uint256[] memory inputAmounts,
        uint256 stalkPenaltyBdv
    ) internal {

        MultiCrateDepositData memory mcdd;

        mcdd.amountPerBdv = amount.div(LibTokenSilo.beanDenominatedValue(outputToken, amount));
        mcdd.totalAmount = 0;

        for (uint256 i = 0; i < bdvs.length; i++) {
            console.log('_depositTokensForConvertMultiCrate i: ', i);
            // console.log('_depositTokensForConvertMultiCrate bdvs[i]: ', bdvs[i]);
            console.log('_depositTokensForConvertMultiCrate grownStalks[i]: ', grownStalks[i]);
            // console.log('_depositTokensForConvertMultiCrate amount: ', amount);
            // uint256 bdv = bdvs[i];
            require( bdvs[i] > 0 && amount > 0, "Convert: BDV or amount is 0.");
            mcdd.crateAmount = bdvs[i].mul(mcdd.amountPerBdv);
            mcdd.totalAmount = mcdd.totalAmount.add(mcdd.crateAmount);

            //if we're on the last crate, deposit the rest of the amount
            if (i == bdvs.length - 1 && bdvs.length > 1) {
                mcdd.crateAmount = amount.sub(mcdd.totalAmount);
            } else if (i == bdvs.length - 1) {
                mcdd.crateAmount = amount; //if there's only one crate, make sure to deposit the full amount
            }
            
            // console.log('_depositTokensForConvertMultiCrate final mcdd.crateAmount:  ', mcdd.crateAmount);

            // because we're calculating a new token amount, the bdv will not be exactly the same as what we withdrew,
            // so we need to make sure we calculate what the actual deposited BDV is.
            // TODO: investigate and see if we can just use the amountPerBdv variable instead of calculating it again.
            mcdd.depositedBdv = LibTokenSilo.beanDenominatedValue(outputToken, mcdd.crateAmount);
            
            // LibGerminate.Germinate germ;

            // calculate the stem and germination state for the new deposit.
            (int96 stem, LibGerminate.Germinate germ) = LibTokenSilo.calculateStemForTokenFromGrownStalk(outputToken, grownStalks[i], mcdd.depositedBdv);
            
            // increment totals based on germination state, 
            // as well as issue stalk to the user.
            // if the deposit is germinating, only the inital stalk of the deposit is germinating. 
            // the rest is active stalk.
            if (germ == LibGerminate.Germinate.NOT_GERMINATING) {
                LibTokenSilo.incrementTotalDeposited(outputToken, mcdd.crateAmount, mcdd.depositedBdv);
                console.log('minting active stalk, issued from bdv: ', mcdd.depositedBdv.mul(LibTokenSilo.stalkIssuedPerBdv(outputToken)));
                console.log('minting active stalk from grown: ', grownStalks[i]);
                LibSilo.mintActiveStalk(
                    LibTractor._getUser(), 
                    mcdd.depositedBdv.mul(LibTokenSilo.stalkIssuedPerBdv(outputToken)).add(grownStalks[i])
                );
            } else {
                LibTokenSilo.incrementTotalGerminating(outputToken, mcdd.crateAmount, mcdd.depositedBdv, germ);
                // safeCast not needed as stalk is <= max(uint128)
                LibSilo.mintGerminatingStalk(LibTractor._getUser(), uint128(mcdd.depositedBdv.mul(LibTokenSilo.stalkIssuedPerBdv(outputToken))), germ);   
                LibSilo.mintActiveStalk(LibTractor._getUser(), grownStalks[i]);
            }
            LibTokenSilo.addDepositToAccount(
                LibTractor._getUser(),
                outputToken, 
                stem, 
                mcdd.crateAmount,
                mcdd.depositedBdv,
                LibTokenSilo.Transfer.emitTransferSingle
            );

            emit Convert(LibTractor._getUser(), inputToken, outputToken, inputAmounts[i], mcdd.crateAmount);
        }
    }
}
