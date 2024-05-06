/*
 SPDX-License-Identifier: MIT
*/

pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @author Publius
 * @title Mock Token
 **/
contract MockToken is ERC20, ERC20Burnable, ERC20Permit {
    uint8 private _decimals = 18;
    string private _symbol = "MOCK";
    string private _name = "MockToken";

    constructor(
        string memory name,
        string memory __symbol
    ) ERC20(name, __symbol) ERC20Permit(name) {}

    function mint(address account, uint256 amount) external returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burnFrom(address account, uint256 amount) public override(ERC20Burnable) {
        ERC20Burnable.burnFrom(account, amount);
    }

    function burn(uint256 amount) public override {
        ERC20Burnable.burn(amount);
    }

    function setDecimals(uint256 dec) public {
        _decimals = uint8(dec);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setSymbol(string memory sym) public {
        _symbol = sym;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function setName(string memory name_) public {
        _name = name_;
    }
}
