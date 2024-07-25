/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.20;

import "../ReentrancyGuard.sol";
import {Invariable} from "contracts/beanstalk/Invariable.sol";
import {IBean} from "contracts/interfaces/IBean.sol";

/**
 * @author Brean
 * @title BeanL2MigrationFacet
 * @notice Allows farmers with external bean balances to migrate onto L2.
 * @dev When migrating to an L2, given a majority of bean assets reside in the diamond contract,
 * beanstalk is able to send these assets to an L2. Beanstalk does not have control of Bean or Wells
 * where tokens are paired with Beans. Given beanstalk cannot receive these assets, as well as a potenital
 * double-spend if Beanstalk were to mint external beans to these users (where a user is able to sell their
 * L1 Beans for value), Beanstalk allows Farmers who hold Beans to 1) Burn their Beans on L1 and 2) Issue the
 * same amount on L2.
 *
 * While this can be done by implmentating an ERC20 bridge solution, ideally the two Beans are not linked via an
 * L2 bridge.
 *
 * The Facet implmentation may need to change depending on the L2 that the beanstalk DAO chooses to migrate to.
 **/

interface IL2Bridge {
    function sendMessage(address _target, bytes memory _message, uint32 _minGasLimit) external;
}

interface IBeanL1RecieverFacet {
    function recieveL1Beans(address reciever, uint256 amount) external;

    function approveReciever(address reciever, uint256 amount) external;
}

contract BeanL2MigrationFacet is Invariable, ReentrancyGuard {
    address constant BRIDGE = address(0x866E82a600A1414e583f7F13623F1aC5d58b0Afa);
    address constant L1_BEAN = address(0xBEA0000029AD1c77D3d5D23Ba2D8893dB9d1Efab);

    /**
     * @notice migrates `amount` of Beans to L2,
     * issued to `reciever`.
     */
    function migrateL2Beans(
        address reciever,
        address L2Beanstalk,
        uint256 amount,
        uint32 gasLimit
    ) external nonReentrant {
        IBean(L1_BEAN).burnFrom(msg.sender, amount);

        // send data to L2Beanstalk via the bridge contract.
        IL2Bridge(BRIDGE).sendMessage(
            L2Beanstalk,
            abi.encodeCall(IBeanL1RecieverFacet(L2Beanstalk).recieveL1Beans, (reciever, amount)),
            gasLimit
        );
    }

    /**
     * @notice allows a contract to approve an address on L2 to recieve their Beanstalk assets.
     * @dev Beanstalk cannot assume that owners of a contract are able to have access to the same address on L2.
     * Thus, contracts that own Beanstalk Assets must approve an address on L2 to recieve their assets.
     */
    function approveL2Reciever(
        address reciever,
        address L2Beanstalk,
        uint256 gasLimit
    ) external nonReentrant {
        require(hasCode(msg.sender), "BeanL2MigrationFacet: must be a contract");
        // send data to L2Beanstalk via the bridge contract.
        IL2Bridge(BRIDGE).sendMessage(
            L2Beanstalk,
            abi.encodeCall(
                IBeanL1RecieverFacet(L2Beanstalk).approveReciever,
                (msg.sender, reciever)
            ),
            gasLimit
        );
    }

    /**
     * @notice checks whether an address has code.
     */
    function hasCode(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}
