// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "@forge-std/Test.sol";
import {AuraAirdrop} from "src/AuraAirdrop.sol";
import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {DeployAuraAirdrop} from "script/DeployAuraAirdrop.s.sol";

contract TestAuraAirdrop is Test {
    DeployAuraAirdrop deploy;
    AuraAirdrop auraAirdrop;
    AuraPowerToken airDropToken;
    bytes32 constant MERKLE_ROOT = 0xdef7050d26c38d24eb6a8ae026530ed4bf0eb5c189e14cd3b13d342dc345e7de;
    // uint256 constant AMOUNT_TO_MINT=100 ether;
    uint256 constant AMOUNT_TO_CLAIM = 25 ether;
    address private constant ANVIL_WALLET = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    bytes32 p1 = 0x4fd31fee0e75780cd67704fbc43caee70fddcaa43631e2e1bc9fb233fada2394;
    bytes32 p2 = 0xcc0f56019b961fdd926625540e969dd2bf1539e77db604e5de77c926e0c54193;
    bytes32[] proof = [p1, p2];

    address user = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 privateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address public gaspayer;

    function setUp() public {
        deploy = new DeployAuraAirdrop();
        (auraAirdrop, airDropToken) = deploy.run();
        gaspayer = makeAddr("gaspayer");
    }

    function testFundsInAirdropContract() public view {
        uint256 balance = airDropToken.balanceOf(address(auraAirdrop));
        assertEq(balance, AMOUNT_TO_CLAIM * 4);
    }

    function testOneCanClaimAirdrop() public {
        vm.prank(user);
        bytes32 digest = auraAirdrop.getMessageHash(user, AMOUNT_TO_CLAIM);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        vm.prank(gaspayer);
        auraAirdrop.claim(user, AMOUNT_TO_CLAIM, proof, v, r, s);

        uint256 balanceOfAirdropContract = airDropToken.balanceOf(address(auraAirdrop));
        uint256 balanceOfUser = airDropToken.balanceOf(user);
        assertEq(balanceOfAirdropContract, AMOUNT_TO_CLAIM * 3);
        assertEq(balanceOfUser, AMOUNT_TO_CLAIM);
    }

    function testMerkleRootIsCorrect() public view {
        bytes32 root = auraAirdrop.getMerkleRoot();
        assertEq(root, MERKLE_ROOT);
    }

    function testAirdropContractAddressIsCorrect() public view {
        address tokenAddress = auraAirdrop.getAirdropTokenAddress();
        assertEq(tokenAddress, address(airDropToken));
    }
}
