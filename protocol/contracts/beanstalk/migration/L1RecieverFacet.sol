/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.20;

import {C} from "contracts/C.sol";
import {ReentrancyGuard} from "../ReentrancyGuard.sol";
import {Field} from "contracts/beanstalk/storage/Account.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {LibSilo} from "contracts/libraries/Silo/LibSilo.sol";
import {LibTractor} from "contracts/libraries/LibTractor.sol";
import {MigrationData} from "contracts/beanstalk/storage/System.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {LibBalance} from "contracts/libraries/Token/LibBalance.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibTokenSilo} from "contracts/libraries/Silo/LibTokenSilo.sol";
import {LibWhitelistedTokens} from "contracts/libraries/Silo/LibWhitelistedTokens.sol";

/**
 * @author Brean
 * @title
 * @notice Allows Beanstalk to recieve data from an L1. see {L2MigrationFacet} for more details.
 * Beanstalk-native assets contract owners can delegate their assets to a reciever address on L2,
 * in order to migrate their deposits, plots, fertilizer, and internal balances to L2.
 **/

interface IL2Messenger {
    function xDomainMessageSender() external view returns (address);
}

contract L1RecieverFacet is ReentrancyGuard {
    // todo: update with correct external beans once L1 Beanstalk has been paused.
    uint256 constant EXTERNAL_L1_BEANS = 1000000e6;

    address constant BRIDGE = address(0x4200000000000000000000000000000000000007);
    address constant L1BEANSTALK = address(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);

    // todo: update with correct merkle roots once once L1 Beanstalk has been paused.
    bytes32 internal constant DEPOSIT_MERKLE_ROOT =
        0xffe91be2b2c070885dbf2f8b4a7b82966d0ff6d91961734a506d1cf1fb80478d;
    bytes32 internal constant PLOT_MERKLE_ROOT =
        0xffe91be2b2c070885dbf2f8b4a7b82966d0ff6d91961734a506d1cf1fb80478d;
    bytes32 internal constant FERTILIZER_MERKLE_ROOT =
        0xffe91be2b2c070885dbf2f8b4a7b82966d0ff6d91961734a506d1cf1fb80478d;
    bytes32 internal constant INTERNAL_BALANCE_MERKLE_ROOT =
        0xffe91be2b2c070885dbf2f8b4a7b82966d0ff6d91961734a506d1cf1fb80478d;

    /**
     * @notice emitted when L1 Beans are migrated to L2.
     */
    event L1BeansMigrated(address indexed reciever, uint256 amount);

    /**
     * @notice emitted when an account recieves a deposit(s) from L1.
     */
    event L1DepositsMigrated(
        address indexed owner,
        address indexed reciever,
        uint256[] depositIds,
        uint256[] amounts,
        uint256[] bdvs
    );

    /**
     * @notice emitted when an account recieves a plot(s) from L1.
     */
    event L1PlotsMigrated(
        address indexed owner,
        address indexed reciever,
        uint256[] index,
        uint256[] pods
    );

    /**
     * @notice emitted when an account recieves internal balances from L1.
     */
    event L1InternalBalancesMigrated(
        address indexed owner,
        address indexed reciever,
        address[] tokens,
        uint256[] amounts
    );

    /**
     * @notice emitted when an account recieves fertilizer from L1.
     */
    event L1FertilizerMigrated(
        address indexed owner,
        address indexed reciever,
        uint256[] fertIds,
        uint128[] amounts,
        uint128 lastBpf
    );

    /**
     * @notice emitted when an account approves a reciever to recieve their assets.
     */
    event RecieverApproved(address indexed owner, address reciever);

    /**
     * @dev Claims the Grown Stalk for user.
     */
    modifier mowAll() {
        address[] memory tokens = LibWhitelistedTokens.getWhitelistedTokens();
        for (uint256 i; i < tokens.length; i++) {
            LibSilo._mow(LibTractor._user(), tokens[i]);
        }
        _;
    }

    /**
     * @notice migrates `amount` of Beans to L2,
     * issued to `reciever`.
     */
    function recieveL1Beans(address reciever, uint256 amount) external nonReentrant {
        // verify msg.sender is the cross-chain messenger address, and
        // the xDomainMessageSender is the L1 Beanstalk contract.
        require(
            msg.sender == address(BRIDGE) &&
                IL2Messenger(BRIDGE).xDomainMessageSender() == L1BEANSTALK
        );
        s.sys.l2migration.migratedL1Beans += amount;
        require(
            EXTERNAL_L1_BEANS >= s.sys.l2migration.migratedL1Beans,
            "L2Migration: exceeds maximum migrated"
        );
        C.bean().mint(reciever, amount);

        emit L1BeansMigrated(reciever, amount);
    }

    /**
     * @notice approves a reciever to recieve the beanstalk native assets of a sender.
     */
    function approveReciever(address owner, address reciever) external nonReentrant {
        // verify msg.sender is the cross-chain messenger address, and
        // the xDomainMessageSender is the L1 Beanstalk contract.
        require(
            msg.sender == address(BRIDGE) &&
                IL2Messenger(BRIDGE).xDomainMessageSender() == L1BEANSTALK
        );

        s.sys.l2migration.account[owner].reciever = reciever;

        emit RecieverApproved(owner, reciever);
    }

    /**
     * @notice issues deposits to `reciever`. Uses a merkle tree in order to verify deposits.
     * @dev global silo variables (`totalDeposited` and `totalDepositedBdv`) do not need to be updated,
     * as the deposits were included in the initial L2 Migration.
     */
    function issueDeposits(
        address owner,
        uint256[] calldata depositIds,
        uint256[] calldata amounts,
        uint256[] calldata bdvs,
        uint256 stalk,
        bytes32[] calldata proof
    ) external mowAll nonReentrant {
        MigrationData storage account = s.sys.l2migration.account[owner];
        address reciever = LibTractor._user();
        require(
            account.reciever != address(0) && account.reciever == reciever,
            "L2Migration: Invalid Reciever"
        );
        require(!account.migratedDeposits, "L2Migration: Deposits have been migrated");

        // verify depositId and amount validity:
        require(
            verifyDepositMerkleProof(owner, depositIds, amounts, bdvs, proof),
            "invalid deposits"
        );

        // add migrated deposits to the account.
        addMigratedDepositsToAccount(reciever, depositIds, amounts, bdvs);

        // increment receiver stalk:
        LibSilo.mintActiveStalk(reciever, stalk);

        // set migrated deposits to true.
        account.migratedDeposits = true;

        emit L1DepositsMigrated(owner, reciever, depositIds, amounts, bdvs);
    }

    /**
     * @notice issues plots to `reciever`. Uses a merkle tree in order to verify plots.
     * @dev global field variables (`totalUnharvested`) do not need to be updated,
     * as the plots were included in the initial L2 Migration.
     */
    function issuePlots(
        address owner,
        uint256[] calldata index,
        uint256[] calldata pods,
        bytes32[] calldata proof
    ) external nonReentrant {
        MigrationData storage account = s.sys.l2migration.account[owner];
        address reciever = LibTractor._user();
        require(
            account.reciever != address(0) && account.reciever == reciever,
            "L2Migration: Invalid Reciever"
        );
        require(!account.migratedPlots, "L2Migration: Plots have been migrated");

        // verify index and pods validity:
        require(verifyPlotMerkleProof(owner, index, pods, proof), "L2Migration: Invalid plots");

        // add migrated plots to the account.
        addMigratedPlotsToAccount(reciever, index, pods);

        // set migrated plots to true.
        account.migratedPlots = true;
        emit L1PlotsMigrated(owner, reciever, index, pods);
    }

    /**
     * @notice issues InternalBalances to `reciever`. Uses a merkle tree in order to verify plots.
     * @dev global internal balance variables (`internalTokenBalanceTotal`) do not need to be updated,
     * as the internal balances were included in the initial L2 Migration.
     */
    function issueInternalBalances(
        address owner,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata proof
    ) external nonReentrant {
        MigrationData storage account = s.sys.l2migration.account[owner];
        address reciever = LibTractor._user();
        require(
            account.reciever != address(0) && account.reciever == reciever,
            "L2Migration: Invalid Reciever"
        );
        require(
            !account.migratedInternalBalances,
            "L2Migration: Internal Balances have been migrated"
        );

        // verify internal balances validity:
        require(
            verifyInternalBalanceMerkleProof(owner, tokens, amounts, proof),
            "L2Migration: Invalid internal balances"
        );

        // add migrated internal balances to the account.
        addMigratedInternalBalancesToAccount(reciever, tokens, amounts);

        // set migrated internal balances to true.
        account.migratedInternalBalances = true;
        emit L1InternalBalancesMigrated(owner, reciever, tokens, amounts);
    }

    /**
     * @notice issues Fertilizer to `reciever`. Uses a merkle tree in order to verify plots.
     * @dev global internal balance variables (`fertilizer, unfertilizedIndex`, etc) do not need to be updated,
     * as the internal balances were included in the initial L2 Migration.
     */
    function issueFertilizer(
        address owner,
        uint256[] calldata fertIds,
        uint128[] calldata amounts,
        uint128 lastBpf,
        bytes32[] calldata proof
    ) external nonReentrant {
        MigrationData storage account = s.sys.l2migration.account[owner];
        address reciever = LibTractor._user();
        require(
            account.reciever != address(0) && account.reciever == reciever,
            "L2Migration: Invalid Reciever"
        );
        require(!account.migratedFert, "L2Migration: Fertilizer have been migrated");

        // verify internal balances validity:
        require(
            verifyFertilizerMerkleProof(owner, fertIds, amounts, lastBpf, proof),
            "L2Migration: Invalid Fertilizer"
        );

        // add migrated internal balances to the account.
        addMigratedFertilizerToAccount(msg.sender, fertIds, amounts, lastBpf);

        // set migrated internal balances to true.
        account.migratedFert = true;
        emit L1FertilizerMigrated(owner, msg.sender, fertIds, amounts, lastBpf);
    }

    //////////// MERKLE PROOF VERIFICATION ////////////

    /**
     * @notice verifies the Deposit merkle proof is valid.
     */
    function verifyDepositMerkleProof(
        address owner,
        uint256[] calldata depositIds,
        uint256[] calldata amounts,
        uint256[] calldata bdvs,
        bytes32[] calldata proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(owner, depositIds, amounts, bdvs)))
        );
        return MerkleProof.verify(proof, DEPOSIT_MERKLE_ROOT, leaf);
    }

    /**
     * @notice verifies the Plot merkle proof is valid.
     */
    function verifyPlotMerkleProof(
        address owner,
        uint256[] calldata index,
        uint256[] calldata amounts,
        bytes32[] calldata proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(owner, index, amounts))));
        return MerkleProof.verify(proof, PLOT_MERKLE_ROOT, leaf);
    }

    /**
     * @notice verifies the InternalBalance merkle proof is valid.
     */
    function verifyInternalBalanceMerkleProof(
        address owner,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(owner, tokens, amounts))));
        return MerkleProof.verify(proof, INTERNAL_BALANCE_MERKLE_ROOT, leaf);
    }

    /**
     * @notice verifies the Fertilizer merkle proof is valid.
     */
    function verifyFertilizerMerkleProof(
        address owner,
        uint256[] calldata fertIds,
        uint128[] calldata amounts,
        uint128 lastBpf,
        bytes32[] calldata proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(owner, fertIds, amounts, lastBpf)))
        );
        return MerkleProof.verify(proof, FERTILIZER_MERKLE_ROOT, leaf);
    }

    //////////// MIGRATION HELPERS ////////////

    /**
     * @notice adds the migrated deposits to the account.
     */
    function addMigratedDepositsToAccount(
        address reciever,
        uint256[] calldata depositIds,
        uint256[] calldata amounts,
        uint256[] calldata bdvs
    ) internal {
        for (uint i; i < depositIds.length; i++) {
            (address token, int96 stem) = LibBytes.unpackAddressAndStem(depositIds[i]);
            LibTokenSilo.addDepositToAccount(
                reciever,
                token,
                stem,
                amounts[i],
                bdvs[i],
                LibTokenSilo.Transfer.emitTransferSingle
            );
        }
    }

    /**
     * @notice adds the migrated deposits to the account.
     */
    function addMigratedPlotsToAccount(
        address reciever,
        uint256[] calldata index,
        uint256[] calldata pods
    ) internal {
        uint256 activeField = s.sys.activeField;
        Field storage field = s.accts[reciever].fields[activeField];
        for (uint i; i < index.length; i++) {
            field.plots[index[i]] = pods[i];
            field.plotIndexes.push(index[i]);
            field.piIndex[index[i]] = field.plotIndexes.length - 1;
        }
    }

    /**
     * @notice adds the migrated internal balances to the account.
     */
    function addMigratedInternalBalancesToAccount(
        address reciever,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) internal {
        for (uint i; i < tokens.length; i++) {
            LibBalance.increaseInternalBalance(reciever, IERC20(tokens[i]), amounts[i]);
        }
    }

    /**
     * @notice adds the migrated Fertilizer to the account.
     */
    function addMigratedFertilizerToAccount(
        address reciever,
        uint256[] calldata fertIds,
        uint128[] calldata amounts,
        uint128 lastBpf
    ) internal {
        for (uint i; i < fertIds.length; i++) {
            C.fertilizer().beanstalkMint(reciever, fertIds[i], amounts[i], lastBpf);
        }
    }

    function getReciever(address owner) external view returns (address) {
        return s.sys.l2migration.account[owner].reciever;
    }

    /**
     * @notice returns the deposit Merkle Root.
     */
    function getDepositMerkleRoot() external pure returns (bytes32) {
        return DEPOSIT_MERKLE_ROOT;
    }

    /**
     * @notice returns the Plot Merkle Root.
     */
    function getPlotMerkleRoot() external pure returns (bytes32) {
        return PLOT_MERKLE_ROOT;
    }

    /**
     * @notice returns the Fertilizer Merkle Root.
     */
    function getFertilizerMerkleRoot() external pure returns (bytes32) {
        return FERTILIZER_MERKLE_ROOT;
    }

    /**
     * @notice returns the Internal Balance Merkle Root.
     */
    function getInternalBalanceMerkleRoot() external pure returns (bytes32) {
        return INTERNAL_BALANCE_MERKLE_ROOT;
    }
}
