// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "@forge-std/Test.sol";
import {DeployAuraGovernor} from "script/DeployAuraGovernor.s.sol";
import {TimeLock} from "src/TimeLock.sol";
import {AuraGovernor} from "src/AuraGovernor.sol";
import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {DeployAuraEngine} from "script/DeployAuraEngine.s.sol";

contract AuraGovernanceTest is Test {
    DeployAuraGovernor public deploy;
    TimeLock public timeLock;
    AuraPowerToken public auraPowerToken;
    AuraGovernor public auraGovernor;
    DeployAuraEngine public deployAuraEngine;
    AuraEngine public auraEngine;

    uint256[] values;
    bytes[] callDatas;
    address[] targets;

    address public constant DEFAULT_OWNER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    uint256 constant AMOUNT_TO_MINT_INITIALLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50400;

    address public USER = makeAddr("user");

    function setUp() public {
        deploy = new DeployAuraGovernor();
        (timeLock, auraGovernor, auraPowerToken) = deploy.run();

        deployAuraEngine = new DeployAuraEngine();
        (, auraEngine,,) = deployAuraEngine.run();
        vm.prank(USER);
        auraPowerToken.delegate(USER);
    }

    function testProposalIsGettingCreatedSuccessfully() public {
        vm.startPrank(DEFAULT_OWNER);
        auraPowerToken.mint(USER, AMOUNT_TO_MINT_INITIALLY);
        auraEngine.transferOwnership(address(timeLock));
        uint8 newLiquidationThreshold = 20;
        string memory description = "need to change the liquidation threshold";
        bytes memory callData =
            abi.encodeWithSelector(auraEngine.updateTheLiquidationThreshold.selector, newLiquidationThreshold);
        targets.push(address(auraEngine));
        callDatas.push(callData);
        values.push(0);
        vm.stopPrank();

        uint256 proposalId = auraGovernor.propose(targets, values, callDatas, description);

        console2.log("Proposal State 1: ", uint256(auraGovernor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        string memory reason = "Because the liquidation thereshold is small ";
        uint8 myVote = 1; // in favor

        vm.prank(USER);
        auraGovernor.castVoteWithReason(proposalId, myVote, reason);

        console2.log("Proposal State 2: ", uint256(auraGovernor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console2.log("Proposal State3: ", uint256(auraGovernor.state(proposalId)));
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        auraGovernor.queue(targets, values, callDatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        auraGovernor.execute(targets, values, callDatas, descriptionHash);

        assertEq(auraEngine.getThresholdHealthFactor(), 20);
    }
}
