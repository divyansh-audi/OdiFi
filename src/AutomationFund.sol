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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {AuraEngine} from "src/AuraEngine.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title Automation Fund
 * @author Divyansh Audichya
 * @notice This contract will be the one which is reponsible to liquidate the users of protocol in the initial phase of the protocol when there are not much users in the protocol to maintain it .
 * It will work like this :
 * 1. The chainlink automation will check for the conditions (checkUpkeep)
 * 2. If found someone with broken health factor ,liquidate it
 * 3. The aura token will be funded to this contract at the time of the deployment so that it can liquidate users using it
 * 4. Once deployed the ownership will be passed on to the Timelock contract
 * 5. And the people of the protocol will design when to collect the collateral and mint and transfer more aura coin to this contract
 */
contract AutomationFund is Ownable {
    /*///////////////////////////////////////
                   ERRORS
    ///////////////////////////////////////*/

    error AutomationFund__MustBeMoreThanZero();
    error AutomationFund__ApprovalFailed();
    error AutomationFund__AmountIsMoreThanBalance();
    error AutomationFund__TransferFailed();

    /*///////////////////////////////////////
                   EVENTS
    ///////////////////////////////////////*/
    event CollateralWithdrawedFromVault(
        address indexed collateralAddress, uint256 indexed amount, address indexed targetAddress
    );

    event CollateralApproved(address indexed collateralAddress, address indexed spender, uint256 indexed amount);

    /*///////////////////////////////////////
                   MODIFIERS
    ///////////////////////////////////////*/

    modifier shouldBeMoreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert AutomationFund__MustBeMoreThanZero();
        }
        _;
    }

    /*///////////////////////////////////////
                   FUNCTIONS
    ///////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    /**
     * This function will be used to take the collateral out of this contract and send it to the AuraEngine contract ,and it will be decided by the community ,how much and which collateral to transfer
     * @param collateralAddress Collateral to be pulled out from this contract
     * @param amount the amount of the collateral to pull out
     * @param to The contract to which you wannt send fund
     *
     * @notice the tranfer function is like a push feature ,like you can push your assets to some other contract using this thing
     */
    function withdrawCollateral(address collateralAddress, uint256 amount, address to)
        external
        onlyOwner
        shouldBeMoreThanZero(amount)
    {
        uint256 contractBalance = IERC20(collateralAddress).balanceOf(address(this));
        if (amount > contractBalance) {
            revert AutomationFund__AmountIsMoreThanBalance();
        }
        bool success = IERC20(collateralAddress).transfer(to, amount);
        if (!success) {
            revert AutomationFund__TransferFailed();
        }
        emit CollateralWithdrawedFromVault(collateralAddress, amount, to);
    }

    /**
     * @dev This function is approving the engine contract to spend the tokens(which means it can tranfer it too) .
     * @param collateralAddress Address of collateral token
     * @param spender The contract which can spend the tokens
     * @param amount amount of ERC-20 token
     *
     * @notice The approveEngine is like pull ,you can approve some contract to pull assests which that contract can spend .
     * Here in this example ,the AuraCoin will be pulled out by the auraEngine so in order for the auraEngine to pull the tokens from this address ,this address need to approve the auraEngine to pull the tokens .
     */
    function approveEngine(address collateralAddress, address spender, uint256 amount)
        external
        onlyOwner
        shouldBeMoreThanZero(amount)
    {
        bool success = IERC20(collateralAddress).approve(spender, amount);
        if (!success) {
            revert AutomationFund__ApprovalFailed();
        }
        emit CollateralApproved(collateralAddress, spender, amount);
    }
}
