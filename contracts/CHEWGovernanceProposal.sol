// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @notice RestaurantAccounts Interface
 */
interface IRestaurantAccounts {
    function updateProfitMargin(uint256 newValue) external;
    function updateMonthlyRent(uint256 newValue) external;
    function updateMonthlyUtilities(uint256 newValue) external;
    function updateDividendRatio(uint256 newValue) external;
    function executeApprovedExpense(address recipient, uint256 amount, string memory reason) external;
    function transferReserveToOperating(uint256 amount, string memory reason) external;
}

/**
 * @title GovernanceProposal
 * @notice DAO governance proposal and voting system (Simplified)
 * @dev CHEW holders can create proposals and vote, requiring 60% approval for execution
 */
contract GovernanceProposal is AccessControl, ReentrancyGuard {
    
    // ===== Constants =====
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant APPROVAL_THRESHOLD = 60;
    
    // ===== Proposal Types =====
    enum ProposalType {
        ADJUST_PROFIT_MARGIN,
        ADJUST_RENT,
        ADJUST_UTILITIES,
        CHANGE_DIVIDEND_RATIO,
        LARGE_EXPENSE,
        USE_RESERVE
    }
    
    // ===== Proposal Structure =====
    struct Proposal {
        uint256 id;
        ProposalType pType;
        address proposer;
        string description;
        uint256 snapshotBlock;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bytes data;
    }
    
    // ===== Vote Choice =====
    enum VoteChoice { Against, For, Abstain }
    
    // ===== State =====
    IVotes public immutable chewToken;
    IRestaurantAccounts public restaurantAccounts;
    
    uint256 public nextProposalId = 1;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    // ===== Events =====
    event ProposalCreated(uint256 indexed proposalId, ProposalType pType, string description);
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteChoice choice, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    
    constructor(address _chewToken, address _restaurantAccounts) {
        require(_chewToken != address(0) && _restaurantAccounts != address(0), "Invalid addresses");
        chewToken = IVotes(_chewToken);
        restaurantAccounts = IRestaurantAccounts(_restaurantAccounts);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    // ===== Create Proposals =====
    
    function createProposal(
        ProposalType pType,
        string memory description,
        bytes memory data
    ) public nonReentrant returns (uint256) {
        require(bytes(description).length > 0 && bytes(description).length <= 500, "Invalid description");
        require(chewToken.getVotes(msg.sender) > 0, "No voting power");
        
        uint256 id = nextProposalId++;
        
        proposals[id] = Proposal({
            id: id,
            pType: pType,
            proposer: msg.sender,
            description: description,
            snapshotBlock: block.number,
            endTime: block.timestamp + VOTING_PERIOD,
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            data: data
        });
        
        emit ProposalCreated(id, pType, description);
        return id;
    }
    
    function proposeParameterChange(
        ProposalType pType,
        string memory description,
        uint256 newValue
    ) external returns (uint256) {
        return createProposal(pType, description, abi.encode(newValue));
    }
    
    function proposeLargeExpense(
        string memory description,
        address recipient,
        uint256 amount,
        string memory reason
    ) external returns (uint256) {
        return createProposal(ProposalType.LARGE_EXPENSE, description, abi.encode(recipient, amount, reason));
    }
    
    function proposeUseReserve(
        string memory description,
        uint256 amount,
        string memory reason
    ) external returns (uint256) {
        return createProposal(ProposalType.USE_RESERVE, description, abi.encode(amount, reason));
    }
    
    // ===== Voting =====
    
    function vote(uint256 proposalId, VoteChoice choice) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "Proposal not found");
        require(!p.executed, "Already executed");
        require(block.timestamp < p.endTime, "Voting ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        
        uint256 weight = chewToken.getPastVotes(msg.sender, p.snapshotBlock);
        require(weight > 0, "No voting power");
        
        hasVoted[proposalId][msg.sender] = true;
        
        if (choice == VoteChoice.For) {
            p.forVotes += weight;
        } else if (choice == VoteChoice.Against) {
            p.againstVotes += weight;
        }
        
        emit VoteCast(proposalId, msg.sender, choice, weight);
    }
    
    // ===== Execution =====
    
    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(p.id != 0, "Proposal not found");
        require(!p.executed, "Already executed");
        require(block.timestamp >= p.endTime, "Voting not ended");
        
        uint256 total = p.forVotes + p.againstVotes;
        require(total > 0, "No votes");
        require((p.forVotes * 100) / total >= APPROVAL_THRESHOLD, "Not approved");
        
        p.executed = true;
        
        if (p.pType == ProposalType.ADJUST_PROFIT_MARGIN) {
            restaurantAccounts.updateProfitMargin(abi.decode(p.data, (uint256)));
        } else if (p.pType == ProposalType.ADJUST_RENT) {
            restaurantAccounts.updateMonthlyRent(abi.decode(p.data, (uint256)));
        } else if (p.pType == ProposalType.ADJUST_UTILITIES) {
            restaurantAccounts.updateMonthlyUtilities(abi.decode(p.data, (uint256)));
        } else if (p.pType == ProposalType.CHANGE_DIVIDEND_RATIO) {
            restaurantAccounts.updateDividendRatio(abi.decode(p.data, (uint256)));
        } else if (p.pType == ProposalType.LARGE_EXPENSE) {
            (address r, uint256 a, string memory reason) = abi.decode(p.data, (address, uint256, string));
            restaurantAccounts.executeApprovedExpense(r, a, reason);
        } else if (p.pType == ProposalType.USE_RESERVE) {
            (uint256 a, string memory reason) = abi.decode(p.data, (uint256, string));
            restaurantAccounts.transferReserveToOperating(a, reason);
        }
        
        emit ProposalExecuted(proposalId);
    }
    
    // ===== View Functions =====
    
    function isApproved(uint256 proposalId) external view returns (bool) {
        Proposal memory p = proposals[proposalId];
        uint256 total = p.forVotes + p.againstVotes;
        if (total == 0) return false;
        return (p.forVotes * 100) / total >= APPROVAL_THRESHOLD;
    }
    
    function getProposal(uint256 proposalId) external view returns (
        ProposalType pType,
        address proposer,
        string memory description,
        uint256 endTime,
        uint256 forVotes,
        uint256 againstVotes,
        bool executed
    ) {
        Proposal memory p = proposals[proposalId];
        return (p.pType, p.proposer, p.description, p.endTime, p.forVotes, p.againstVotes, p.executed);
    }
    
    function getVotingPower(uint256 proposalId, address account) external view returns (uint256) {
        return chewToken.getPastVotes(account, proposals[proposalId].snapshotBlock);
    }
}