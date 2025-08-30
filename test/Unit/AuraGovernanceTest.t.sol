// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "@forge-std/Test.sol";
import {AuraGovernanceDiamond} from "src/AuraGovernanceDiamond.sol";
import {TimeLock} from "src/TimeLock.sol";
import {DeployDiamondGovernance} from "script/DeployDiamondGovernance.s.sol";

import {AuraPowerToken} from "src/AuraPowerToken.sol";
import {AuraEngine} from "src/AuraEngine.sol";
import {DeployAuraEngine} from "script/DeployAuraEngine.s.sol";
import {GovernanceCoreFacet} from "src/facets/GovernanceCoreFacet.sol";
import {GovernanceTimelockFacet} from "src/facets/GovernanceTimelockFacet.sol";

contract AuraGovernanceTest is Test {
    DeployDiamondGovernance public deploy;
    TimeLock public timeLock;
    AuraPowerToken public auraPowerToken;
    AuraGovernanceDiamond public auraGovernanceDiamond;
    DeployAuraEngine public deployAuraEngine;
    AuraEngine public auraEngine;
    // GovernanceTimelockFacet public governanceTimelockFacet;

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
        deploy = new DeployDiamondGovernance();
        (timeLock, auraPowerToken,,,,, auraGovernanceDiamond) = deploy.run();
        deployAuraEngine = new DeployAuraEngine();
        (, auraEngine,,) = deployAuraEngine.run();
        vm.prank(DEFAULT_OWNER);
        auraPowerToken.delegate(DEFAULT_OWNER);
    }

    function testProposalIsGettingCreatedSuccessfully() public {
        vm.startPrank(DEFAULT_OWNER);
        auraPowerToken.mint(USER, AMOUNT_TO_MINT_INITIALLY);
        auraPowerToken.mint(DEFAULT_OWNER, AMOUNT_TO_MINT_INITIALLY);
        auraEngine.transferOwnership(address(timeLock));
        uint8 newLiquidationThreshold = 25;
        // uint8 prevLiquidationThreshold=
        string memory description = "need to change the liquidation threshold";
        bytes memory callData =
            abi.encodeWithSelector(auraEngine.updateTheLiquidationThreshold.selector, newLiquidationThreshold);
        targets.push(address(auraEngine));
        callDatas.push(callData);
        values.push(0);
        vm.stopPrank();

        vm.prank(DEFAULT_OWNER);
        GovernanceCoreFacet(address(auraGovernanceDiamond)).initialize(
            address(auraPowerToken), address(timeLock), VOTING_DELAY, VOTING_PERIOD, 0, 0
        );

        uint256 proposalId =
            GovernanceCoreFacet(address(auraGovernanceDiamond)).propose(targets, values, callDatas, description);

        console2.log(
            "Proposal State 1: ", uint256(GovernanceCoreFacet(address(auraGovernanceDiamond)).state(proposalId))
        );

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        string memory reason = "Because the liquidation thereshold is small ";
        uint8 myVote = 1; // in favor

        vm.prank(USER);
        GovernanceCoreFacet(address(auraGovernanceDiamond)).castVoteWithReason(proposalId, myVote, reason);

        vm.prank(DEFAULT_OWNER);
        GovernanceCoreFacet(address(auraGovernanceDiamond)).castVoteWithReason(proposalId, myVote, reason);

        console2.log(
            "Proposal State 2: ", uint256(GovernanceCoreFacet(address(auraGovernanceDiamond)).state(proposalId))
        );

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console2.log(
            "Proposal State3: ", uint256(GovernanceCoreFacet(address(auraGovernanceDiamond)).state(proposalId))
        );
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        GovernanceTimelockFacet(address(auraGovernanceDiamond)).queue(targets, values, callDatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        vm.prank(address(timeLock));
        GovernanceTimelockFacet(address(auraGovernanceDiamond)).execute(targets, values, callDatas, descriptionHash);

        assertEq(auraEngine.getThresholdHealthFactor(), 25);
    }
}
