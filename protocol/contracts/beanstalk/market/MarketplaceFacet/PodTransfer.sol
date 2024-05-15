/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.20;

import "contracts/libraries/LibRedundantMath256.sol";
import "contracts/beanstalk/AppStorage.sol";
import "contracts/interfaces/IBean.sol";
import "contracts/libraries/LibRedundantMath32.sol";
import "contracts/beanstalk/ReentrancyGuard.sol";
import "contracts/C.sol";

/**
 * @author Publius
 * @title Pod Transfer
 **/

contract PodTransfer is ReentrancyGuard {
    using LibRedundantMath256 for uint256;
    using LibRedundantMath32 for uint32;

    event PlotTransfer(address indexed from, address indexed to, uint256 indexed id, uint256 pods);
    event PodApproval(address indexed owner, address indexed spender, uint256 pods);

    /**
     * Getters
     **/

    function allowancePods(address owner, address spender) public view returns (uint256) {
        return s.accounts[owner].field.podAllowances[spender];
    }

    /**
     * Internal
     **/

    function _transferPlot(
        address from,
        address to,
        uint256 index,
        uint256 start,
        uint256 amount
    ) internal {
        require(from != to, "Field: Cannot transfer Pods to oneself.");
        insertPlot(to, index.add(start), amount);
        removePlot(from, index, start, amount.add(start));
        emit PlotTransfer(from, to, index.add(start), amount);
    }

    function insertPlot(address account, uint256 id, uint256 amount) internal {
        s.accounts[account].field.plots[id] = amount;
    }

    function removePlot(address account, uint256 id, uint256 start, uint256 end) internal {
        uint256 amount = s.accounts[account].field.plots[id];
        if (start == 0) delete s.accounts[account].field.plots[id];
        else s.accounts[account].field.plots[id] = start;
        if (end != amount) s.accounts[account].field.plots[id.add(end)] = amount.sub(end);
    }

    function decrementAllowancePods(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowancePods(owner, spender);
        if (currentAllowance < amount) {
            revert("Field: Insufficient approval.");
        }
        setAllowancePods(owner, spender, currentAllowance.sub(amount));
    }

    function setAllowancePods(address owner, address spender, uint256 amount) internal {
        s.accounts[owner].field.podAllowances[spender] = amount;
    }
}
