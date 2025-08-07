// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev This will going to represent a STABLE COIN whose price will be pegged to `₹1` (i.e. 1 Indian Rupee) and it will be governed by AuraEngine.
 * @title AuraCoin
 * @author Divyansh Audichya
 * This Contract is an ERC-20 token which has burn and mint function. It is ownable and can only be controlled by the Engine contract.
 *
 * Collateral Exogeneous(ETH)
 * Minting:Algorithmic
 * Relative Stablity: Pegged to INR
 */
contract AuraCoin is ERC20Burnable, Ownable {
    /*///////////////////////////////////////
                    ERRORS
    ///////////////////////////////////////*/

    error AuraCoin__InvalidAddressForMintingTokens();
    error AuraCoin__AmountShouldBeMoreThanZero();
    error AuraCoin__InsufficientBalanceToBurn();

    /*///////////////////////////////////////
                   MODIFIER
    ///////////////////////////////////////*/

    modifier amountShouldBeMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert AuraCoin__AmountShouldBeMoreThanZero();
        }
        _;
    }

    /*///////////////////////////////////////
                   FUNCTIONS
    ///////////////////////////////////////*/

    constructor() ERC20("AuraCoin", "AUC") Ownable(msg.sender) {}

    /*///////////////////////////////////////
                EXTERNAL FUNCTIONS
    ///////////////////////////////////////*/

    /**
     * @param _to address where AuraCoin have to be minted
     * @param _amount Amount of Coin to be minted
     */
    function mint(address _to, uint256 _amount) external onlyOwner amountShouldBeMoreThanZero(_amount) returns (bool) {
        if (_to == address(0)) {
            revert AuraCoin__InvalidAddressForMintingTokens();
        }
        _mint(_to, _amount);
        return true;
    }

    /**
     * @dev In this burn function ,we didn't used the burnFrom function ,because of the reasons:-
     * 1. If someone is redeeming it's collateral then the transaction (i.e. burning) will be initiated by itself only ,this case is simple .
     * 2. If a liquidator is calling the liquidate function ,the liquidator will going to burn it's own Stable Coin in order to get the collateral and bonus .
     * @param _amount The amount of token one has to burn when user is redeeming it's collateral or when someone is liquidating .
     */
    function burn(uint256 _amount) public override onlyOwner amountShouldBeMoreThanZero(_amount) {
        if (_amount > balanceOf(msg.sender)) {
            revert AuraCoin__InsufficientBalanceToBurn();
        }
        super.burn(_amount);
    }
}
