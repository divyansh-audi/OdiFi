// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console2} from "@forge-std/Script.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {LibGovernanceStorage} from "../libraries/LibGovernanceStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/**
 * @title GovernanceCoreFacet
 * @author Divyansh Audichya
 * @notice This contract is the same structure as that of OpenZeppelin's Governance Contract.
 */
contract GovernanceCoreFacet {
    using LibGovernanceStorage for LibGovernanceStorage.GovernanceStorage;

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function initialize(
        address _token,
        address _timelock,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumNumerator
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();

        gs.token = _token;
        gs.timelock = _timelock;
        gs.votingDelay = _votingDelay;
        gs.votingPeriod = _votingPeriod;
        gs.proposalThreshold = _proposalThreshold;
        gs.quorumNumerator = _quorumNumerator;
        gs.quorumDenominator = 100;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        console2.log(msg.sender);
        console2.log(block.number - 1);
        console2.log(proposalThreshold());
        require(
            IVotes(gs.token).getPastVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        console2.log("Inside the delegate call");
        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        require(gs.proposals[proposalId].id == 0, "Governor: proposal already exists");

        uint256 startBlock = block.number + gs.votingDelay;
        uint256 endBlock = startBlock + gs.votingPeriod;

        gs.proposals[proposalId] = LibGovernanceStorage.ProposalCore({
            id: proposalId,
            proposer: msg.sender,
            eta: 0,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            canceled: false,
            executed: false
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            startBlock,
            endBlock,
            description
        );

        return proposalId;
    }

    function castVote(uint256 proposalId, uint8 support) public returns (uint256) {
        return _castVote(proposalId, msg.sender, support, "");
    }

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) public returns (uint256) {
        return _castVote(proposalId, msg.sender, support, reason);
    }

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason)
        internal
        returns (uint256)
    {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();

        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");
        require(!gs.hasVoted[proposalId][account], "Governor: vote already cast");

        uint256 weight = IVotes(gs.token).getPastVotes(account, gs.proposals[proposalId].startBlock);

        gs.hasVoted[proposalId][account] = true;

        if (support == 0) {
            gs.proposals[proposalId].againstVotes += weight;
        } else if (support == 1) {
            gs.proposals[proposalId].forVotes += weight;
        } else if (support == 2) {
            gs.proposals[proposalId].abstainVotes += weight;
        } else {
            revert("Governor: invalid value for enum VoteType");
        }

        emit VoteCast(account, proposalId, support, weight, reason);

        return weight;
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        LibGovernanceStorage.ProposalCore storage proposal = gs.proposals[proposalId];

        require(proposal.id != 0, "Governor: unknown proposal id");

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 startBlock = proposal.startBlock;

        if (startBlock >= block.number) {
            return ProposalState.Pending;
        }

        uint256 endBlock = proposal.endBlock;

        if (endBlock >= block.number) {
            return ProposalState.Active;
        }
        console2.log("quorum reached:", _quorumReached(proposalId));
        console2.log("vote succeded:", _voteSucceeded(proposalId));
        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }

    function proposalThreshold() public view returns (uint256) {
        return LibGovernanceStorage.governanceStorage().proposalThreshold;
    }

    function quorum(uint256 blockNumber) public view returns (uint256) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        uint256 totalSupply = IVotes(gs.token).getPastTotalSupply(blockNumber);
        return (totalSupply * gs.quorumNumerator) / gs.quorumDenominator;
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        LibGovernanceStorage.ProposalCore storage proposal = gs.proposals[proposalId];

        uint256 totalVotes = proposal.forVotes + proposal.abstainVotes + proposal.againstVotes;
        return totalVotes >= quorum(proposal.startBlock);
    }

    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        LibGovernanceStorage.GovernanceStorage storage gs = LibGovernanceStorage.governanceStorage();
        LibGovernanceStorage.ProposalCore storage proposal = gs.proposals[proposalId];

        return proposal.forVotes > proposal.againstVotes;
    }

    function getProposal(uint256 proposalId) external view returns (LibGovernanceStorage.ProposalCore memory) {
        return LibGovernanceStorage.governanceStorage().proposals[proposalId];
    }
}
