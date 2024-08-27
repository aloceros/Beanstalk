// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import {TestHelper, LibTransfer, C, IMockFBeanstalk} from "test/foundry/utils/TestHelper.sol";
import {L1RecieverFacet} from "contracts/beanstalk/migration/L1RecieverFacet.sol";
import {LibBytes} from "contracts/Libraries/LibBytes.sol";
import {IMockFBeanstalk} from "contracts/interfaces/IMockFBeanstalk.sol";
import "forge-std/console.sol";
import {Deposit} from "contracts/beanstalk/storage/Account.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Verfifies state and functionality of the new L2 Beanstalk
 */
contract ReseedTest is TestHelper {
    // contracts for testing:
    address constant L2_BEANSTALK = address(0xD1A0060ba708BC4BCD3DA6C37EFa8deDF015FB70);
    address constant FERTILIZER = address(0xC59f881074Bf039352C227E21980317e6b969c8A);

    uint256 constant FIELD_ID = 0;

    address constant L2BEAN = address(0xBEA0005B8599265D41256905A9B3073D397812E4);
    address constant L2URBEAN = address(0x1BEA054dddBca12889e07B3E076f511Bf1d27543);
    address constant L2URLP = address(0x1BEA059c3Ea15F6C10be1c53d70C75fD1266D788);

    address[] whiteListedWellTokens = [
        address(0xBEA00ebA46820994d24E45dffc5c006bBE35FD89), // BEAN/WETH
        address(0xBEA0039bC614D95B65AB843C4482a1A5D2214396), // BEAN/WstETH
        address(0xBEA000B7fde483F4660041158D3CA53442aD393c), // BEAN/WEETH
        address(0xBEA0078b587E8f5a829E171be4A74B6bA1565e6A), // BEAN/WBTC
        address(0xBEA00C30023E873D881da4363C00F600f5e14c12), // BEAN/USDC
        address(0xBEA00699562C71C2d3fFc589a848353151a71A61) // BEAN/USDT
    ];

    address[] whitelistedTokens = [
        L2BEAN,
        L2URBEAN,
        L2URLP,
        address(0xBEA00ebA46820994d24E45dffc5c006bBE35FD89), // BEAN/WETH
        address(0xBEA0039bC614D95B65AB843C4482a1A5D2214396), // BEAN/WstETH
        address(0xBEA000B7fde483F4660041158D3CA53442aD393c), // BEAN/WEETH
        address(0xBEA0078b587E8f5a829E171be4A74B6bA1565e6A), // BEAN/WBTC
        address(0xBEA00C30023E873D881da4363C00F600f5e14c12), // BEAN/USDC
        address(0xBEA00699562C71C2d3fFc589a848353151a71A61) // BEAN/USDT
    ];

    IMockFBeanstalk l2Beanstalk;

    string constant HEX_PREFIX = "0x";

    string constant ACCOUNTS_PATH = "./test/foundry/Migration/data/accounts.txt";

    address constant DEFAULT_ACCOUNT = address(0xC5581F1aE61E34391824779D505Ca127a4566737);

    uint256 accountNumber;

    function setUp() public {
        // parse accounts and populate the accounts.txt file
        accountNumber = parseAccounts();
        l2Beanstalk = IMockFBeanstalk(L2_BEANSTALK);
        // l2Beanstalk.gm(address(this), 1);
    }

    ////////////////// WhiteListed Tokens //////////////////

    function test_whiteListedTokens() public {
        // all whitelisted tokens
        address[] memory tokens = l2Beanstalk.getWhitelistedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i], whitelistedTokens[i]);
        }
        // all whitelisted lp tokens
        address[] memory whitelistedLpTokens = l2Beanstalk.getWhitelistedLpTokens();
        for (uint256 i = 0; i < whitelistedLpTokens.length; i++) {
            assertEq(whitelistedLpTokens[i], whiteListedWellTokens[i]);
        }
        // all whitelisted well lp tokens (should be the same)
        address[] memory whitelistedWellLpTokens = l2Beanstalk.getWhitelistedWellLpTokens();
        for (uint256 i = 0; i < whitelistedWellLpTokens.length; i++) {
            assertEq(whitelistedWellLpTokens[i], whiteListedWellTokens[i]);
        }
    }

    //////////////////// Global State Silo ////////////////////

    function test_totalStalk() public {
        uint256 totalStalk = l2Beanstalk.totalStalk();
        bytes memory totalStalkJson = searchGlobalPropertyData("silo.stalk");
        // decode the stalk from json
        uint256 totalStalkJsonDecoded = vm.parseUint(vm.toString(totalStalkJson));
        assertEq(totalStalk, totalStalkJsonDecoded);
    }

    function test_totalEarnedBeans() public {
        bytes memory earnedBeansJson = searchGlobalPropertyData("silo.earnedBeans");
        uint256 earnedBeans = l2Beanstalk.totalEarnedBeans();
        // decode the earnedBeans from json
        uint256 earnedBeansJsonDecoded = vm.parseUint(vm.toString(earnedBeansJson));
        assertEq(earnedBeans, earnedBeansJsonDecoded);
    }

    function test_totalRoots() public {
        uint256 roots = l2Beanstalk.totalRoots();
        bytes memory rootsJson = searchGlobalPropertyData("silo.roots");
        // decode the roots from json
        uint256 rootsJsonDecoded = vm.parseUint(vm.toString(rootsJson));
        assertEq(roots, rootsJsonDecoded);
    }

    //////////////////// Global State Season ////////////////////

    function test_seasonNumber() public {
        uint32 season = l2Beanstalk.season();
        bytes memory seasonJson = searchGlobalPropertyData("season.current");
        // decode the season from json
        uint32 seasonJsonDecoded = uint32(vm.parseUint(vm.toString(seasonJson)));
        assertEq(season, seasonJsonDecoded);
    }

    //////////////////// Global State Field ////////////////////

    function test_maxTemperature() public {
        uint256 maxTemperature = l2Beanstalk.maxTemperature();
        bytes memory maxTemperatureJson = searchGlobalPropertyData("weather.temp");
        // decode the maxTemperature from json
        uint256 maxTemperatureJsonDecoded = vm.parseUint(vm.toString(maxTemperatureJson));
        // add precision to the temperaturejson to match the maxTemperature
        maxTemperatureJsonDecoded = maxTemperatureJsonDecoded * 1e6;
        assertEq(maxTemperature, maxTemperatureJsonDecoded);
    }

    function test_totalSoil() public {
        uint256 soil = l2Beanstalk.totalSoil();
        bytes memory soilJson = searchGlobalPropertyData("soil");
        // soil will be 0 before the oracle is initialized
        assertEq(soil, 0);
    }

    // pods
    function test_totalPods() public {
        uint256 pods = l2Beanstalk.totalPods(FIELD_ID);
        bytes memory podsJson = searchGlobalPropertyData("fields.0.pods");
        // decode the pods from json
        uint256 podsJsonDecoded = vm.parseUint(vm.toString(podsJson));
        assertEq(pods, podsJsonDecoded);
    }

    function test_totalHarvested() public {
        uint256 harvested = l2Beanstalk.totalHarvested(FIELD_ID);
        bytes memory harvestedJson = searchGlobalPropertyData("fields.0.harvested");
        // decode the harvested from json
        uint256 harvestedJsonDecoded = vm.parseUint(vm.toString(harvestedJson));
        assertEq(harvested, harvestedJsonDecoded);
    }

    //////////////////// Account State //////////////////////

    function test_AccountStalk() public {
        string memory account;
        uint256 accountStalk;
        for (uint256 i = 0; i < 1000; i++) {
            account = vm.readLine(ACCOUNTS_PATH);
            accountStalk = l2Beanstalk.balanceOfStalk(vm.parseAddress(account));
            // get stalk from json
            string memory accountStalkPath = string.concat(account, ".stalk");
            bytes memory accountStalkJson = searchAccountPropertyData(accountStalkPath);
            // decode the stalk from json
            uint256 accountStalkJsonDecoded = vm.parseUint(vm.toString(accountStalkJson));
            assertEq(accountStalk, accountStalkJsonDecoded);
        }
    }

    function test_AccountRoots() public {
        string memory account;
        uint256 accountRoots;
        for (uint256 i = 0; i < accountNumber; i++) {
            account = vm.readLine(ACCOUNTS_PATH);
            accountRoots = l2Beanstalk.balanceOfRoots(vm.parseAddress(account));
            // get roots from json
            string memory accountRootsPath = string.concat(account, ".roots");
            bytes memory accountRootsJson = searchAccountPropertyData(accountRootsPath);
            // decode the roots from json
            uint256 accountRootsJsonDecoded = vm.parseUint(vm.toString(accountRootsJson));
            assertEq(accountRoots, accountRootsJsonDecoded);
        }
    }

    ///////////////// Account Internal Balance ////////////////////

    function test_AccountInternalBalance() public {
        string memory account;
        for (uint256 i = 0; i < accountNumber; i++) {
            account = vm.readLine(ACCOUNTS_PATH);
            for (uint256 j = 0; j < whitelistedTokens.length; j++) {
                // get the internal balance for the account
                uint256 tokenInternalBalance = l2Beanstalk.getInternalBalance(
                    vm.parseAddress(account),
                    whitelistedTokens[j]
                );
                // get the internal balance from json
                string memory accountInternalBalancePath = string.concat(
                    account,
                    ".internalTokenBalance."
                );
                accountInternalBalancePath = string.concat(
                    accountInternalBalancePath,
                    vm.toString(whitelistedTokens[j])
                );
                bytes memory accountInternalBalanceJson = searchAccountPropertyData(
                    accountInternalBalancePath
                );
                // decode the internal balance from json
                uint256 accountInternalBalanceJsonDecoded = vm.parseUint(
                    vm.toString(accountInternalBalanceJson)
                );
                assertEq(tokenInternalBalance, accountInternalBalanceJsonDecoded);
            }
        }
    }

    //////////////////// Account Plots ////////////////////

    function test_AccountPlots() public {
        // test the L2 Beanstalk
        string memory account;
        for (uint256 i = 0; i < accountNumber; i++) {
            account = vm.readLine(ACCOUNTS_PATH);
            console.log("Checking account: ", account);
            IMockFBeanstalk.Plot[] memory plots = l2Beanstalk.getPlotsFromAccount(
                vm.parseAddress(account),
                FIELD_ID
            );
            console.log("plots count: ", plots.length);
            for (uint256 i = 0; i < plots.length; i++) {
                console.log("index: ", plots[i].index);
                console.log("pods: ", plots[i].pods);
            }
        }
    }

    //////////////////// Account Deposits ////////////////////

    function test_getDepositsForAccount() public {
        // test the L2 Beanstalk
        IMockFBeanstalk.TokenDepositId[] memory tokenDeposits = l2Beanstalk.getDepositsForAccount(
            address(DEFAULT_ACCOUNT)
        );
        console.log("Checking account: ", address(DEFAULT_ACCOUNT));
        console.log("token deposits count: ", tokenDeposits.length);
        for (uint256 i = 0; i < tokenDeposits.length; i++) {
            console.log("token: ", tokenDeposits[i].token);
            console.log("depositIds count: ", tokenDeposits[i].depositIds.length);
            for (uint256 j = 0; j < tokenDeposits[i].depositIds.length; j++) {
                console.log("depositId: ", tokenDeposits[i].depositIds[j]);
            }
        }
    }

    //////////////////// Helpers ////////////////////

    function parseAccounts() public returns (uint256) {
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "./test/foundry/Migration/data/getAccounts.js"; // script
        bytes memory res = vm.ffi(inputs);
        // decode the number of accounts
        uint256 accountNumber = vm.parseUint(vm.toString(res));
        return accountNumber;
    }

    function searchGlobalPropertyData(string memory property) public returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "./test/foundry/Migration/finderScripts/finder.js"; // script
        inputs[2] = "./reseed/data/exports/storage-system20577510.json"; // json file
        inputs[3] = property;
        bytes memory propertyValue = vm.ffi(inputs);
        return propertyValue;
    }

    function searchAccountPropertyData(string memory property) public returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "./test/foundry/Migration/finderScripts/finder.js"; // script
        inputs[2] = "./reseed/data/exports/storage-accounts20577510.json"; // json file
        inputs[3] = property;
        bytes memory propertyValue = vm.ffi(inputs);
        return propertyValue;
    }

    function searchAccountPlots(string memory account) public returns (bytes memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "./test/foundry/Migration/finderScripts/finder.js"; // script
        inputs[2] = "./reseed/data/exports/storage-accounts20577510.json"; // json file
        inputs[3] = account;
        bytes memory accountPlots = vm.ffi(inputs);
        return accountPlots;
    }
}
