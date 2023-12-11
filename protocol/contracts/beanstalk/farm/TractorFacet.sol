/// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

// TODO rm
// import "forge-std/console.sol";
import "hardhat/console.sol";

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "../ReentrancyGuard.sol";
import "../../libraries/LibBytes.sol";
import {LibTractor} from "../../libraries/LibTractor.sol";
import {AdvancedFarmCall, LibFarm} from "../../libraries/LibFarm.sol";
import {LibOperatorPasteInstr} from "../../libraries/LibOperatorPasteInstr.sol";

/**
 * @title TractorFacet handles tractor and blueprint operations.
 * @author 0xm00neth
 */
contract TractorFacet is ReentrancyGuard {
    using LibOperatorPasteInstr for bytes32;
    /*********/
    /* Enums */
    /*********/

    /// @notice Blueprint type enum
    enum BlueprintType {
        NULL,
        ADVANCED_FARM
    }

    /**********/
    /* Events */
    /**********/

    /// @dev Emitted on publishRequisition()
    event PublishRequisition(LibTractor.Requisition requisition);

    /// @dev Emitted on cancelBlueprint()
    event CancelBlueprint(bytes32 blueprintHash);

    /// @dev Emitted on tractor()
    event Tractor(address indexed operator, bytes32 blueprintHash);

    /*************/
    /* Modifiers */
    /*************/

    modifier verifyRequisition(LibTractor.Requisition calldata requisition) {
        bytes32 blueprintHash = LibTractor._getBlueprintHash(requisition.blueprint);
        require(blueprintHash == requisition.blueprintHash, "TractorFacet: invalid hash");
        address signer = ECDSA.recover(
            ECDSA.toEthSignedMessageHash(requisition.blueprintHash),
            requisition.signature
        );
        require(signer == requisition.blueprint.publisher, "TractorFacet: invalid signer");
        _;
    }

    /// @notice Check blueprint nonce, increment nonce, handle active publisher.
    modifier runBlueprint(LibTractor.Requisition calldata requisition) {
        require(
            LibTractor._getBlueprintNonce(requisition.blueprintHash) <
                requisition.blueprint.maxNonce,
            "TractorFacet: maxNonce reached"
        );
        require(
            requisition.blueprint.startTime <= block.timestamp &&
                block.timestamp <= requisition.blueprint.endTime,
            "TractorFacet: blueprint is not active"
        );
        LibTractor._incrementBlueprintNonce(requisition.blueprintHash);
        LibTractor._setPublisher(requisition.blueprint.publisher);
        _;
        LibTractor._resetPublisher();
    }

    /******************/
    /* User Functions */
    /******************/

    /// @notice Publish new blueprint
    /// Emits {PublishRequisition} event
    function publishRequisition(
        LibTractor.Requisition calldata requisition
    ) external verifyRequisition(requisition) {
        emit PublishRequisition(requisition);
    }

    /// @notice Destroy existing blueprint
    /// Emits {CancelBlueprint} event
    function cancelBlueprint(
        LibTractor.Requisition calldata requisition
    ) external verifyRequisition(requisition) {
        require(msg.sender == requisition.blueprint.publisher, "TractorFacet: not publisher");
        LibTractor._cancelBlueprint(requisition.blueprintHash);
        emit CancelBlueprint(requisition.blueprintHash);
    }

    /// @notice Tractor Operation
    /// Emits {Tractor} event
    function tractor(
        LibTractor.Requisition calldata requisition,
        bytes memory operatorData
    )
        external
        payable
        verifyRequisition(requisition)
        runBlueprint(requisition)
        returns (bytes[] memory results)
    {
        console.log("HERE1");
        // extract blueprint type and publisher data from blueprint.data.
        // bytes1 blueprintType = blueprint.data[0]; // TODO we are not using type
        console.logBytes(requisition.blueprint.data);
        bytes memory blueprintData = LibBytes.sliceFrom(requisition.blueprint.data, 1);
        require(blueprintData.length > 0, "Tractor: blueprint data empty");

        console.log("HERE2");

        // Decode and execute advanced farm calls.
        // Cut out blueprint data type and calldata selector. Keep location and length (it is a dynamically sized
        // object or dynamically sized objects).
        // bytes[] memory splitData;
        // // NOTE this decode fails silently - decoding with a diff type array has undefined behavior.
        // splitData = abi.decode(LibBytes.sliceFrom(requisition.blueprint.data, 1 + 4), (bytes[]));
        // console.log("splitData before pastes");
        // for (uint256 i = 0; i < splitData.length; ++i) {
        //     console.logBytes(splitData[i]);
        // }
        // NOTE this decode works
        AdvancedFarmCall[] memory calls = abi.decode(
            LibBytes.sliceFrom(requisition.blueprint.data, 1 + 4),
            (AdvancedFarmCall[])
        );

        // TODO improve memory efficiency by manually digging into the bytes and splitting them up using read lengths.

        console.log("HERE3");

        // Update data with operator-defined fillData.
        // TODO how does iterating over a bytes object work? Here we assume each 32 byte slot is one object.
        for (uint256 i; i < requisition.blueprint.operatorPasteInstrs.length; ++i) {
            bytes32 operatorPasteInstr = requisition.blueprint.operatorPasteInstrs[i];
            // require(calls.length > pasteCallIndex, "PB: pasteCallIndex out of bounds");
            // NOTE pass by reference ?
            LibOperatorPasteInstr.pasteBytes(
                operatorPasteInstr,
                operatorData,
                calls[operatorPasteInstr.pasteCallIndex()].callData
            );
        }

        console.log("HERE4");

        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            require(calls[i].callData.length != 0, "TractorFacet: Empty AdvancedFarmCall");
            console.logBytes(calls[i].callData);
            results[i] = LibFarm._advancedFarmMem(calls[i], results);
        }

        console.log("HERE5");

        emit Tractor(msg.sender, requisition.blueprintHash);
    }

    /// @notice return current blueprint nonce
    /// @return nonce current blueprint nonce
    function getBlueprintNonce(bytes32 blueprintHash) external view returns (uint256) {
        return LibTractor._getBlueprintNonce(blueprintHash);
    }

    /// @notice return EIP712 hash of the blueprint
    /// @return hash calculated Blueprint hash
    function getBlueprintHash(
        LibTractor.Blueprint calldata blueprint
    ) external view returns (bytes32) {
        return LibTractor._getBlueprintHash(blueprint);
    }
}
