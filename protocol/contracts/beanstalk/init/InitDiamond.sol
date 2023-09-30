/*
 SPDX-License-Identifier: MIT
*/

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import {AppStorage, Storage} from "../AppStorage.sol";
import {IERC165} from "../../interfaces/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IDiamondCut} from "../../interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../interfaces/IDiamondLoupe.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {LibIncentive} from "../../libraries/LibIncentive.sol";
import "../../C.sol";
import "../../interfaces/IBean.sol";
import "../../interfaces/IWETH.sol";
import "../../mocks/MockToken.sol";

/**
 * @author Publius
 * @title Init Diamond initializes the Beanstalk Diamond.
**/
contract InitDiamond {

    event Incentivization(address indexed account, uint256 beans);

    AppStorage internal s;

    address private constant PEG_PAIR = address(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    function init() external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[0xd9b67a26] = true; // ERC1155
        ds.supportedInterfaces[0x0e89341c] = true; // ERC1155Metadata


        C.bean().approve(C.CURVE_BEAN_METAPOOL, type(uint256).max);
        C.bean().approve(C.curveZapAddress(), type(uint256).max);
        C.usdc().approve(C.curveZapAddress(), type(uint256).max);

    //     s.cases = [
    //    Dsc, Sdy, Inc, nul
    //    int8(3),   1,   0,   0,  // Exs Low: P < 1
    //         -1,  -3,  -3,   0,  //          P > 1
    //          3,   1,   0,   0,  // Rea Low: P < 1
    //         -1,  -3,  -3,   0,  //          P > 1
    //          3,   3,   1,   0,  // Rea Hgh: P < 1
    //          0,  -1,  -3,   0,  //          P > 1
    //          3,   3,   1,   0,  // Exs Hgh: P < 1
    //          0,  -1,  -3,   0   //          P > 1
    //     ];

        s.casesV2 = [
    //                Dsc soil demand,  Steady soil demand     Inc soil demand
    //                [mT][bT][mL][bL]    [mT][bT][mL][bL]    [mT][bT][mL][bL]
                    ///////////////// Exremely Low L2SR ///////////////////////
            bytes8(0x2710000327100032), 0x2710000127100032, 0x2710000027100032, // Exs Low: P < 1
                    0x2710ffff27100032, 0x2710fffd27100032, 0x2710fffd27100032, //          P > 1
                    0x2710ffff27100032, 0x2710fffd27100032, 0x2710fffd27100032, //          P > Q
                    0x2710000327100032, 0x2710000127100032, 0x2710000027100032, // Rea Low: P < 1
                    0x2710ffff27100032, 0x2710fffd27100032, 0x2710fffd27100032, //          P > 1
                    0x2710ffff27100032, 0x2710fffd27100032, 0x2710fffd27100032, //          P > Q
                    0x2710000327100032, 0x2710000327100032, 0x2710000127100032, // Rea Hgh: P < 1
                    0x2710000027100032, 0x2710ffff27100032, 0x2710fffd27100032, //          P > 1
                    0x2710000027100032, 0x2710ffff27100032, 0x2710fffd27100032, //          P > Q
                    0x2710000327100032, 0x2710000327100032, 0x2710000127100032, // Exs Hgh: P < 1
                    0x2710000027100032, 0x2710ffff27100032, 0x2710fffd27100032, //          P > 1
                    0x2710000027100032, 0x2710ffff27100032, 0x2710fffd27100032, //          P > Q
                    /////////////////// Reasonably Low L2SR ///////////////////
                    0x2710000327100019, 0x2710000327100019, 0x2710000027100019, // Exs Low: P < 1
                    0x2710ffff27100019, 0x2710fffd27100019, 0x2710fffd27100019, //          P > 1
                    0x2710ffff27100019, 0x2710fffd27100019, 0x2710fffd27100019, //          P > Q
                    0x2710000327100019, 0x2710000327100019, 0x2710000027100019, // Rea Low: P < 1
                    0x2710ffff27100019, 0x2710fffd27100019, 0x2710fffd27100019, //          P > 1
                    0x2710ffff27100019, 0x2710fffd27100019, 0x2710fffd27100019, //          P > Q
                    0x2710000327100019, 0x2710000327100019, 0x2710000327100019, // Rea Hgh: P < 1
                    0x2710000027100019, 0x2710ffff27100019, 0x2710fffd27100019, //          P > 1
                    0x2710000027100019, 0x2710ffff27100019, 0x2710fffd27100019, //          P > Q
                    0x2710000327100019, 0x2710000327100019, 0x2710000327100019, // Exs Hgh: P < 1
                    0x2710000027100019, 0x2710ffff27100019, 0x2710fffd27100019, //          P > 1
                    0x2710000027100019, 0x2710ffff27100019, 0x2710fffd27100019, //          P > Q
                    /////////////////// Reasonably High L2SR //////////////////
                    0x271000032710FFE7, 0x271000032710FFE7, 0x271000002710FFE7, // Exs Low: P < 1
                    0x2710ffff2710FFE7, 0x2710fffd2710FFE7, 0x2710fffd2710FFE7, //          P > 1
                    0x2710ffff2710FFE7, 0x2710fffd2710FFE7, 0x2710fffd2710FFE7, //          P > Q
                    0x271000032710FFE7, 0x271000032710FFE7, 0x271000002710FFE7, // Rea Low: P < 1
                    0x2710ffff2710FFE7, 0x2710fffd2710FFE7, 0x2710fffd2710FFE7, //          P > 1
                    0x2710ffff2710FFE7, 0x2710fffd2710FFE7, 0x2710fffd2710FFE7, //          P > Q
                    0x271000032710FFE7, 0x271000032710FFE7, 0x271000032710FFE7, // Rea Hgh: P < 1
                    0x271000002710FFE7, 0x2710ffff2710FFE7, 0x2710fffd2710FFE7, //          P > 1
                    0x271000002710FFE7, 0x2710ffff2710FFE7, 0x2710fffd2710FFE7, //          P > Q
                    0x271000032710FFE7, 0x271000032710FFE7, 0x271000032710FFE7, // Exs Hgh: P < 1
                    0x271000002710FFE7, 0x2710ffff2710FFE7, 0x2710fffd2710FFE7, //          P > 1
                    0x271000002710FFE7, 0x2710ffff2710FFE7, 0x2710fffd2710FFE7, //          P > Q
                    /////////////////// Extremely High L2SR ///////////////////
                    0x271000032710FFCE, 0x271000032710FFCE, 0x271000002710FFCE, // Exs Low: P < 1
                    0x2710ffff2710FFCE, 0x2710fffd2710FFCE, 0x2710fffd2710FFCE, //          P > 1
                    0x2710ffff2710FFCE, 0x2710fffd2710FFCE, 0x2710fffd2710FFCE, //          P > Q
                    0x271000032710FFCE, 0x271000032710FFCE, 0x271000002710FFCE, // Rea Low: P < 1
                    0x2710ffff2710FFCE, 0x2710fffd2710FFCE, 0x2710fffd2710FFCE, //          P > 1
                    0x2710ffff2710FFCE, 0x2710fffd2710FFCE, 0x2710fffd2710FFCE, //          P > Q
                    0x271000032710FFCE, 0x271000032710FFCE, 0x271000032710FFCE, // Rea Hgh: P < 1
                    0x271000002710FFCE, 0x2710ffff2710FFCE, 0x2710fffd2710FFCE, //          P > 1
                    0x271000002710FFCE, 0x2710ffff2710FFCE, 0x2710fffd2710FFCE, //          P > Q
                    0x271000032710FFCE, 0x271000032710FFCE, 0x271000032710FFCE, // Exs Hgh: P < 1
                    0x271000002710FFCE, 0x2710ffff2710FFCE, 0x2710fffd2710FFCE, //          P > 1
                    0x271000002710FFCE, 0x2710ffff2710FFCE, 0x2710fffd2710FFCE  //          P > Q
        ];

        s.w.t = 1;

        s.season.current = 1;
        s.season.withdrawSeasons = 25;
        s.season.period = C.getSeasonPeriod();
        s.season.timestamp = block.timestamp;
        s.season.start = s.season.period > 0 ?
            (block.timestamp / s.season.period) * s.season.period :
            block.timestamp;

        s.w.thisSowTime = type(uint32).max;
        s.w.lastSowTime = type(uint32).max;
        s.isFarm = 1;
        s.beanEthPrice = 1;
        s.usdEthPrice = 1;
        s.seedGauge.BeanToMaxLpGpPerBDVRatio = 50e6; // 50%
        s.seedGauge.averageGrownStalkPerBdvPerSeason = 1e6;
        s.season.stemStartSeason = uint16(s.season.current);

        C.bean().mint(msg.sender, LibIncentive.MAX_REWARD);
        emit Incentivization(msg.sender, LibIncentive.MAX_REWARD);
    }

}
