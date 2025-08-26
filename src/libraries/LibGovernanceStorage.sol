// SPDX-License-Identifier: SMIT
pragma solidity ^0.8.27;

/**
 * @title LibGovernanceStorage
 * @author Divyansh Audichya
 * @notice This contract is the storage for the Diamond proxy contract and stores all the structs and mappings
 */
library LibGovernanceStorage {
    bytes32 constant GOVERNANCE_STORAGE_POSITION = keccak256("diamond.standard.governance.storage");

    struct GovernanceStorage {
        // Core Governor storage
        mapping(uint256 => ProposalCore) proposals;
        uint256 proposalCount;
        // Settings
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
        // Token and timelock references
        address token;
        address timelock;
        // Quorum settings
        uint256 quorumNumerator;
        uint256 quorumDenominator;
        // Vote counting
        mapping(uint256 => mapping(address => bool)) hasVoted;
        mapping(uint256 => VoteCount) voteCount;
    }

    struct ProposalCore {
        uint256 id;
        address proposer;
        uint256 eta;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
    }

    struct VoteCount {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
    }

    function governanceStorage() internal pure returns (GovernanceStorage storage gs) {
        bytes32 position = GOVERNANCE_STORAGE_POSITION;
        assembly {
            gs.slot := position
        }
    }
}
