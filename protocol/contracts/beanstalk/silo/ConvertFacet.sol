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
import {LibWell} from "contracts/libraries/Well/LibWell.sol";
import {IPipeline, PipeCall} from "contracts/interfaces/IPipeline.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {LibFunction} from "contracts/libraries/LibFunction.sol";
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
    
    struct AssetsRemovedConvert {
        LibSilo.Removed active;
        uint256[] bdvsRemoved;
        uint256[] stalksRemoved;
        uint256[] depositIds;
    }

    struct PipelineConvertData {
        uint256 grownStalk;
        int256 startingCombinedDeltaB;
        int256 endingCombinedDeltaB;
        uint256 inputAmount;
        int256 cappedDeltaB;
        uint256 stalkPenaltyBdv;
        address user;
        uint256 newBdv;
    }

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

        address toToken; address fromToken; uint256 grownStalk;
        (toToken, fromToken, toAmount, fromAmount) = LibConvert.convert(convertData);

        require(fromAmount > 0, "Convert: From amount is 0.");

        require(fromAmount > 0, "Convert: From amount is 0.");

        LibSilo._mow(LibTractor._user(), fromToken);
        LibSilo._mow(LibTractor._user(), toToken);

        (grownStalk, fromBdv) = _withdrawTokens(
            fromToken,
            stems,
            amounts,
            fromAmount
        );

        uint256 newBdv = LibTokenSilo.beanDenominatedValue(toToken, toAmount);
        toBdv = newBdv > fromBdv ? newBdv : fromBdv;

        toStem = _depositTokensForConvert(toToken, toAmount, toBdv, grownStalk);

        emit Convert(LibTractor._user(), fromToken, toToken, fromAmount, toAmount);
    }

    /**
     * @notice Pipeline convert allows any type of convert using a series of
     * pipeline calls. A stalk penalty may be applied if the convert crosses deltaB.
     * 
     * @param inputToken The token to convert from.
     * @param stems The stems of the deposits to convert from.
     * @param amounts The amounts of the deposits to convert from.
     * @param outputToken The token to convert to.
     * @param advancedFarmCalls The farm calls to execute.
     * @return toStem the new stems of the converted deposit
     * @return fromAmount the amount of tokens converted from
     * @return toAmount the amount of tokens converted to
     * @return fromBdv the bdv of the deposits converted from
     * @return toBdv the bdv of the deposit converted to
     */
    function pipelineConvert(
        address inputToken,
        int96[] calldata stems,
        uint256[] calldata amounts,
        address outputToken,
        AdvancedFarmCall[] calldata advancedFarmCalls
    )
        external
        payable
        nonReentrant
        returns (int96 toStem, uint256 fromAmount, uint256 toAmount, uint256 fromBdv, uint256 toBdv)
    {
        // require that input and output tokens be wells (Unripe not supported)
        require(LibWell.isWell(inputToken) || inputToken == C.BEAN, "Convert: Input token must be Bean or a well");
        require(LibWell.isWell(outputToken) || outputToken == C.BEAN, "Convert: Output token must be Bean or a well");


        PipelineConvertData memory pipeData;
        pipeData.user = LibTractor._user();

        // mow input and output tokens: 
        LibSilo._mow(pipeData.user, inputToken);
        LibSilo._mow(pipeData.user, outputToken);
        
        // Calculate the maximum amount of tokens to withdraw
        for (uint256 i = 0; i < stems.length; i++) {
            pipeData.inputAmount = pipeData.inputAmount.add(amounts[i]);
        }

        (pipeData.grownStalk, fromBdv) = _withdrawTokens(
            inputToken,
            stems,
            amounts,
            pipeData.inputAmount
        );

        pipeData.startingCombinedDeltaB = getCombinedDeltaBForTokens(inputToken, outputToken);

        IERC20(inputToken).transfer(C.PIPELINE, pipeData.inputAmount);
        executeAdvancedFarmCalls(advancedFarmCalls);

        // user MUST leave final assets in pipeline, allowing us to verify that the farm has been called successfully.
        // this also let's us know how many assets to attempt to pull out of the final type
        toAmount = transferTokensFromPipeline(outputToken);


        // We want the capped deltaB from all the wells, this is what sets up/limits the overall convert power for the block
        // Converts that either cross peg, OR occur when convert power has been exhausted, will be stalk penalized
        pipeData.cappedDeltaB = LibWellMinting.overallCappedDeltaB();


        pipeData.endingCombinedDeltaB = getCombinedDeltaBForTokens(inputToken, outputToken);

        // Calculate stalk penalty using start/finish deltaB of pools, and the capped deltaB is
        // passed in to setup max convert power.
        pipeData.stalkPenaltyBdv = _calculateStalkPenalty(pipeData.startingCombinedDeltaB, pipeData.endingCombinedDeltaB, fromBdv, abs(pipeData.cappedDeltaB));
        
        // Update grownStalk amount with penalty applied
        pipeData.grownStalk = pipeData.grownStalk.sub(pipeData.stalkPenaltyBdv);

        pipeData.newBdv = LibTokenSilo.beanDenominatedValue(outputToken, toAmount);

        toStem = _depositTokensForConvert(outputToken, toAmount, pipeData.newBdv, pipeData.grownStalk);

        emit Convert(pipeData.user, inputToken, outputToken, pipeData.inputAmount, toAmount);
    }

    /**
     * @notice Returns the multi-block MEV resistant deltaB for a given token using capped reserves from the well.
     * @param well The well for which to return the capped reserves deltaB
     * @return deltaB The capped reserves deltaB for the well
     */
    function cappedReservesDeltaB(
        address well
    ) public view returns (int256 deltaB, uint256[] memory instReserves, uint256[] memory ratios) {
        (deltaB, instReserves, ratios) = LibWellMinting.cappedReservesDeltaB(well);
    }

    // public function for the below
    function calculateStalkPenalty(int256 beforeDeltaB, int256 afterDeltaB, uint256 bdvConverted, uint256 cappedDeltaB)
        external returns (uint256 stalkPenaltyBdv) {
        return _calculateStalkPenalty(beforeDeltaB, afterDeltaB, bdvConverted, cappedDeltaB);
    }

    /**
     * @notice Calculates the percentStalkPenalty for a given convert.
     * @dev The percentStalkPenalty is the amount of Stalk that is lost as a result of converting against
     * or past peg.
     * @param beforeDeltaB The deltaB before the deposit.
     * @param afterDeltaB The deltaB after the deposit.
     * @param bdvConverted The amount of BDVs that were removed, will be summed in this function.
     * @param cappedDeltaB The absolute value of capped deltaB, used to setup per-block conversion limits.
     * @return stalkPenaltyBdv The BDV amount that should be penalized, 0 means no penalty, full bdv returned means all bdv penalized
     */
    function _calculateStalkPenalty(int256 beforeDeltaB, int256 afterDeltaB, uint256 bdvConverted, uint256 cappedDeltaB) internal returns (uint256 stalkPenaltyBdv) {
        // represents how far past peg deltaB was moved
        uint256 crossoverAmount;

        // the bdv amount that was converted against peg
        uint256 amountAgainstPeg = abs(afterDeltaB.sub(beforeDeltaB));

        // we could potentially be right at zero often with automated tractor converts
        if (beforeDeltaB == 0 && afterDeltaB != 0) {
            //this means we converted away from peg, so amount against peg is penalty
            return amountAgainstPeg;
        }

        // Check if the signs of beforeDeltaB and afterDeltaB are different,
        // indicating that deltaB has crossed zero
        if ((beforeDeltaB > 0 && afterDeltaB < 0) || (beforeDeltaB < 0 && afterDeltaB > 0)) {
            // Calculate how far past peg we went - so actually this is just abs of new deltaB
            crossoverAmount = abs(afterDeltaB);

            // Check if the crossoverAmount is greater than or equal to bdvConverted
            // TODO: see if we can find cases where bdcConverted doesn't match the deltaB diff? should always in theory afaict
            if (crossoverAmount > bdvConverted) {
                // If the entire bdvConverted amount crossed over, something is fishy, bdv amounts wrong?
                revert("Convert: converted farther than bdv");
            } else {
                return crossoverAmount;
            }
        } else if (beforeDeltaB <= 0 && afterDeltaB < beforeDeltaB) { 
            return amountAgainstPeg;
        } else if (beforeDeltaB >= 0 && afterDeltaB > beforeDeltaB) { 
            return amountAgainstPeg;
        }

        // at this point we are converting in direction of peg, but we may have gone past it

        // Setup convert power for this block if it has not already been setup
        if (s.convertCapacity[block.number].hasConvertHappenedThisBlock == false) {
            // use capped deltaB for flashloan resistance
            s.convertCapacity[block.number].convertCapacity = uint248(cappedDeltaB);
            s.convertCapacity[block.number].hasConvertHappenedThisBlock = true;
        }

        // calculate how much deltaB convert is happening with this convert
        uint256 convertAmountInDirectionOfPeg = abs(beforeDeltaB.sub(afterDeltaB));

        if (convertAmountInDirectionOfPeg <= s.convertCapacity[block.number].convertCapacity) {
            // all good, you're using less than the available convert power

            // subtract from convert power available for this block
            s.convertCapacity[block.number].convertCapacity -= uint248(convertAmountInDirectionOfPeg);

            return crossoverAmount;
        } else {
            // you're using more than the available convert power

            // penalty will be how far past peg you went, but any remaining convert power is used to reduce the penalty
            uint256 penalty = convertAmountInDirectionOfPeg - s.convertCapacity[block.number].convertCapacity;

            // all convert power for this block is used up
            s.convertCapacity[block.number].convertCapacity = 0;

            return penalty.add(crossoverAmount); // should this be capped at bdvConverted?
        }
    }

    /**
     * @notice Returns currently available convert power for this block
     * @return convertCapacity The amount of convert power available for this block
     */
    function getConvertCapacity() public view returns (uint256) {
        if (s.convertCapacity[block.number].hasConvertHappenedThisBlock == false) {
            // if convert power has not been initialized for this block, use the overall deltaB
            return abs(LibWellMinting.overallCappedDeltaB());
        }
        return s.convertCapacity[block.number].convertCapacity;
    }

    /**
     * @param inputToken The input token for the convert.
     * @param outputToken The output token for the convert.
     * @return combinedDeltaBinsta The combined deltaB of the input/output tokens.
     */
    function getCombinedDeltaBForTokens(address inputToken, address outputToken) internal view
        returns (int256 combinedDeltaBinsta) {
        combinedDeltaBinsta = getInstaDeltaB(inputToken).add(getInstaDeltaB(outputToken));
    }

    /**
     * @param token The token to get the deltaB of.
     * @return instDeltaB The deltaB of the token, for Bean it returns 0.
     */
    function getInstaDeltaB(address token) internal view returns (int256 instDeltaB) {
        if (token == address(C.bean())) {
            return 0;
        }
        instDeltaB = LibWellMinting.instantaneousDeltaB(token);
        return instDeltaB;
    }

    /**
     * @param calls The advanced farm calls to execute.
     */
    function executeAdvancedFarmCalls(AdvancedFarmCall[] calldata calls) internal { 
        bytes[] memory results;
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            require(calls[i].callData.length != 0, "Convert: empty AdvancedFarmCall");
            results[i] = LibFarm._advancedFarmMem(calls[i], results);
        }
    }

    /**
     * @notice Determines input token amount left in pipeline and returns to Beanstalk
     * @param tokenOut The token to pull out of pipeline
     */
    function transferTokensFromPipeline(address tokenOut) private returns (uint256 amountOut) {
        amountOut = IERC20(tokenOut).balanceOf(C.PIPELINE);

        require(amountOut > 0, "Convert: No output tokens left in pipeline");

        // todo investigate not using the entire interface but just using the function selector here
        PipeCall memory p;
        p.target = address(tokenOut); //contract that pipeline will call
        p.data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(this),
            amountOut
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

        IPipeline(C.PIPELINE).pipe(p);
    }

    /**
     * @notice removes the deposits from user and returns the
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
    ) internal returns (uint256, uint256) {
        require(
            stems.length == amounts.length,
            "Convert: stems, amounts are diff lengths."
        );

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
                // skip any stems that are germinating, due to the ability to 
                // circumvent the germination process.
                // TODO: expose a view function that let's you pass in stems/amounts and returns the non-germinating stems/amounts?
                if (germStem.germinatingStem <= stems[i]) {
                    i++;
                    continue;
                }

                if (a.active.tokens.add(amounts[i]) >= maxTokens) amounts[i] = maxTokens.sub(a.active.tokens);
                
                a.bdvsRemoved[i] = LibTokenSilo.removeDepositFromAccount(
                        LibTractor._user(),
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
                
                a.active.tokens = a.active.tokens.add(amounts[i]);
                a.active.bdv = a.active.bdv.add(a.bdvsRemoved[i]);
                
                a.depositIds[i] = uint256(LibBytes.packAddressAndStem(
                    token,
                    stems[i]
                ));
                i++;
            }
            for (i; i < stems.length; ++i) amounts[i] = 0;
            
            emit RemoveDeposits(
                LibTractor._user(),
                token,
                stems,
                amounts,
                a.active.tokens,
                a.bdvsRemoved
            );

            emit LibSilo.TransferBatch(
                LibTractor._user(), 
                LibTractor._user(),
                address(0), 
                a.depositIds, 
                amounts
            );
        }

        require(
            a.active.tokens == maxTokens,
            "Convert: Not enough tokens removed."
        );
        LibTokenSilo.decrementTotalDeposited(token, a.active.tokens, a.active.bdv);

        // all deposits converted are not germinating.
        LibSilo.burnActiveStalk(
            LibTractor._user(),
            a.active.stalk.add(a.active.bdv.mul(s.ss[token].stalkIssuedPerBdv))
        );
        return (a.active.stalk, a.active.bdv);
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
                LibTractor._user(), 
                bdv.mul(LibTokenSilo.stalkIssuedPerBdv(token)).add(grownStalk)
            );
        } else {
            LibTokenSilo.incrementTotalGerminating(token, amount, bdv, germ);
            // safeCast not needed as stalk is <= max(uint128)
            LibSilo.mintGerminatingStalk(LibTractor._user(), uint128(bdv.mul(LibTokenSilo.stalkIssuedPerBdv(token))), germ);   
            LibSilo.mintActiveStalk(LibTractor._user(), grownStalk);
        }
        LibTokenSilo.addDepositToAccount(
            LibTractor._user(), 
            token, 
            stem, 
            amount,
            bdv,
            LibTokenSilo.Transfer.emitTransferSingle
        );        
    }

    // TODO: when we updated to Solidity 0.8, use the native abs function
    // the verson of OpenZeppelin we're on does not support abs
    function abs(int256 a) internal pure returns (uint256) {
        return a >= 0 ? uint256(a) : uint256(-a);
    }
}
