/**
 * SPDX-License-Identifier: MIT
 **/
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "forge-std/Test.sol";

import {Utils} from "test/foundry/utils/Utils.sol";

/**
 * @title DepotDeployer
 * @author Brean
 * @notice Test helper contract to deploy Depot.
 */
contract DepotDeployer is Utils {

    struct DeployData2 {
        string name;
        address functionAddress;
        bytes constructorData;
    }

    address PIPELINE = address(0xb1bE0000C6B3C62749b5F0c92480146452D15423);
    address DEPOT = address(0xDEb0f00071497a5cc9b4A6B96068277e57A82Ae2);

    function initDepot(bool verbose) public {
        
        DeployData2[] memory deploys = new DeployData2[](2);
        
        deploys[0] = DeployData2("Pipeline.sol", PIPELINE, new bytes(0));
        if(verbose) console.log("Pipeline deposited at: %s", PIPELINE);
        deploys[1] = DeployData2("Depot.sol", DEPOT, new bytes(0));
        if(verbose) console.log("Depot deposited at: %s", DEPOT);
        
        for(uint i; i < deploys.length; i++) {
            deployCodeTo(deploys[i].name, deploys[i].constructorData, deploys[i].functionAddress);
        }
    }
}
