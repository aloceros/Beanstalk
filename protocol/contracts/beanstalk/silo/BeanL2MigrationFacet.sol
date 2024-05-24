/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.20;

import "contracts/C.sol";
import "../ReentrancyGuard.sol";

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
    function sendData(bytes memory) external;
}

contract BeanL2MigrationFacet is ReentrancyGuard {
    // TODO: set bridge
    address constant BRIDGE = address(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

    /**
     * @notice migrates `amount` of Beans to L2,
     * issued to `reciever`.
     */
    function migrateL2Beans(address reciever, uint256 amount) external nonReentrant {
        C.bean().burnFrom(msg.sender, amount);

        // send data to
        IL2Bridge(BRIDGE).sendData(abi.encode(reciever, amount));
    }
}
