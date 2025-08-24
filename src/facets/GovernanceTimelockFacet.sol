// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// =============================================================================
// TIMELOCK INTEGRATION FACET
// =============================================================================

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {LibGovernanceStorage} from "../libraries/LibGovernanceStorage.sol";
import {GovernanceCoreFacet} from "./GovernanceCoreFacet.sol";

contract GovernanceTimelockFacet {
    using LibGovernanceStorage for LibGovernanceStorage.GovernanceStorage;

    event ProposalQueued(uint256 proposalId, uint256 eta);
    event ProposalExecuted(uint256 proposalId);

    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        public
        returns (uint256)
    {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(state(proposalId) == GovernanceCoreFacet.ProposalState.Succeeded, "Governor: proposal not successful");

        uint256 delay = TimelockController(payable(gs.timelock)).getMinDelay();
        gs.proposals[proposalId].eta = block.timestamp + delay;

        for (uint256 i = 0; i < targets.length; ++i) {
            TimelockController(payable(gs.timelock)).schedule(
                targets[i],
                values[i],
                calldatas[i],
                0, // predecessor
                keccak256(abi.encode(proposalId, i)), // salt
                delay
            );
        }

        emit ProposalQueued(proposalId, gs.proposals[proposalId].eta);
        return proposalId;
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable returns (uint256) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        require(
            state(proposalId) == GovernanceCoreFacet.ProposalState.Succeeded
                || state(proposalId) == GovernanceCoreFacet.ProposalState.Queued,
            "Governor: proposal not ready"
        );

        gs.proposals[proposalId].executed = true;

        for (uint256 i = 0; i < targets.length; ++i) {
            TimelockController(payable(gs.timelock)).execute(
                targets[i],
                values[i],
                calldatas[i],
                0, // predecessor
                keccak256(abi.encode(proposalId, i)) // salt
            );
        }

        emit ProposalExecuted(proposalId);
        return proposalId;
    }

    // Forward declarations needed
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function state(uint256 proposalId) public view returns (GovernanceCoreFacet.ProposalState) {
        // This would delegate to the core facet in a real implementation
        // For brevity, implementing basic logic here
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        LibGovernanceStorage.ProposalCore storage proposal = gs.proposals[proposalId];

        if (proposal.executed) {
            return GovernanceCoreFacet.ProposalState.Executed;
        }

        if (proposal.eta > 0 && block.timestamp >= proposal.eta) {
            return GovernanceCoreFacet.ProposalState.Queued;
        }

        // Simplified state logic - in practice you'd delegate to core facet
        if (block.number < proposal.endBlock) {
            return GovernanceCoreFacet.ProposalState.Active;
        }

        return GovernanceCoreFacet.ProposalState.Succeeded;
    }
}
