// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "@forge-std/Test.sol";
import {AuraCoin} from "../../src/AuraCoin.sol";

contract AuraCoinTest is Test {
    AuraCoin auraCoin;
    address public ALICE = makeAddr("alice");
    address public BOB = makeAddr("bob");
    uint256 public AMOUNT_TO_MINT = 1 ether;

    function setUp() public {
        vm.startBroadcast(ALICE);
        auraCoin = new AuraCoin();
        vm.stopBroadcast();
        vm.deal(ALICE, AMOUNT_TO_MINT);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(BOB);
        vm.expectRevert();
        auraCoin.mint(BOB, AMOUNT_TO_MINT);

        uint256 balanceBefore = auraCoin.balanceOf(BOB);
        vm.prank(ALICE);
        auraCoin.mint(BOB, AMOUNT_TO_MINT);
        uint256 balanceAfter = auraCoin.balanceOf(BOB);
        assertEq(balanceAfter, balanceBefore + AMOUNT_TO_MINT);
        console2.log("Balance Before:", balanceBefore);
        console2.log("Balance After:", balanceAfter);
    }

    function testRevertIfAmountLessThanZeroOrZero() public {
        vm.prank(ALICE);
        vm.expectRevert(AuraCoin.AuraCoin__AmountShouldBeMoreThanZero.selector);
        auraCoin.mint(BOB, 0);

        vm.startPrank(ALICE);
        auraCoin.mint(ALICE, AMOUNT_TO_MINT);
        uint256 balance = auraCoin.balanceOf(ALICE);
        console2.log("balance:", balance);
        vm.expectRevert(AuraCoin.AuraCoin__InsufficientBalanceToBurn.selector);
        auraCoin.burn(balance * 2);
        vm.stopPrank();
        console2.log("balance:", balance);

        vm.startPrank(ALICE);
        uint256 beforeAmount = auraCoin.balanceOf(ALICE);
        console2.log("balance before burning :", beforeAmount);
        auraCoin.burn(beforeAmount / 2);
        console2.log("balance after burning :", auraCoin.balanceOf(ALICE));
        vm.stopPrank();
        uint256 afterAmount = auraCoin.balanceOf(ALICE);
        assertEq(beforeAmount, afterAmount * 2);
    }

    function testRevertIfMintedToAddressZero() public {
        vm.prank(ALICE);
        vm.expectRevert(AuraCoin.AuraCoin__InvalidAddressForMintingTokens.selector);
        auraCoin.mint(address(0), AMOUNT_TO_MINT);
    }

    function testRevertOnInvalidCall() public {
        bytes memory callData = abi.encodeWithSelector(auraCoin.mint.selector, ALICE, AMOUNT_TO_MINT);
        vm.prank(ALICE);
        // vm.expectRevert(AuraCoin.AuraCoin__AmountShouldBeMoreThanZero.selector);
        (bool success,) = address(auraCoin).call(callData);
        assertEq(success, true);
        // assertEq(address(auraCoin).balance, AMOUNT_TO_MINT);
    }
}
