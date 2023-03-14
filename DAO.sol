// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DAOToken is ERC20, Ownable {
    constructor() ERC20("DAOToken", "DAO") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract DAO is Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    DAOToken public token;

    struct BoardMember {
        address member;
        string role;
    }

    struct Proposal {
        uint256 id;
        string description;
        uint256 amount;
        uint256 payrollTax;
        uint256 deadline;
        bool approved;
        uint256 yesVotes;
        uint256 noVotes;
    }

    struct BoardMemberNomination {
        uint256 id;
        address nominee;
        string proposedRole;
        address proposer;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 deadline;
        bool active;
    }

    address[] public boardMembers;
    mapping(address => BoardMember) public boardMemberDetails;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => BoardMemberNomination) public nominations;

    Counters.Counter private _proposalIds;
    Counters.Counter private _nominationIds;

    uint256 public nominationThreshold;
    uint256 public votingDuration;

    event BoardMemberNominated(uint256 indexed nominationId, address indexed nominee, string proposedRole, address indexed proposer);
    event BoardMemberNominationVote(uint256 indexed nominationId, address indexed voter, bool vote);
    event BoardMemberAdded(uint256 indexed nominationId, address indexed nominee, string role);
    event BoardMemberRemoved(address indexed memberToRemove);

    event BudgetProposalCreated(uint256 indexed proposalId, string description, uint256 amount, uint256 payrollTax, uint256 deadline);
    event BudgetProposalVote(uint256 indexed proposalId, address indexed voter, bool vote);
    event BudgetProposalApproved(uint256 indexed proposalId, uint256 amount, uint256 payrollTax);

    constructor(DAOToken _token) {
        token = _token;
        nominationThreshold = token.totalSupply().mul(5).div(100); // 5% of total token supply
        votingDuration = 7 days;
    }

    modifier onlyBoardMember() {
        require(isBoardMember(msg.sender), "Only board members can perform this action");
        _;
    }

    // Token management functions

    function issueTokens(address recipient, uint256 amount) public onlyOwner {
        token.mint(recipient, amount);
    }

    function transferTokens(address recipient, uint256 amount) public {
        token.transferFrom(msg.sender, recipient, amount);
    }

    // Board member nomination and voting functions

    function nominateBoardMember(address nominee, string memory proposedRole) public {
        require(token.balanceOf(msg.sender) >= nominationThreshold, "Insufficient token balance to nominate a board member");

        _nominationIds.increment();
        uint256 nominationId = _nominationIds.current();

        nominations[nominationId] = BoardMemberNomination({
            id: nominationId,
            nominee: nominee,
            proposedRole: proposedRole,
            proposer: msg.sender,
            yesVotes: 0,
            noVotes: 0,
            deadline: block.timestamp.add(votingDuration),
            active: true
        });

        emit BoardMemberNominated(nominationId, nominee, proposedRole, msg.sender);
    }

    function voteOnNomination(uint256 nominationId, bool vote) public {
        BoardMemberNomination storage nomination = nominations[nominationId];
        require(nomination.active, "Nomination is not active");
        require(block.timestamp <= nomination.deadline, "Voting period has ended");

        if (vote) {
            nomination.yesVotes = nomination.yesVotes.add(token.balanceOf(msg.sender));
        } else {
            nomination.noVotes = nomination.noVotes.add(token.balanceOf(msg.sender));
        }

        emit BoardMemberNominationVote(nominationId, msg.sender, vote);

        if (nomination.yesVotes > token.totalSupply().mul(50).div(100)) { // 50% approval
            boardMembers.push(nomination.nominee);
            boardMemberDetails[nomination.nominee] = BoardMember({member: nomination.nominee, role: nomination.proposedRole});
            nomination.active = false;
            emit BoardMemberAdded(nominationId, nomination.nominee, nomination.proposedRole);
        }
    }

    function removeBoardMember(address memberToRemove) public onlyBoardMember {
        require(isBoardMember(memberToRemove), "Address is not a board member");

        for (uint256 i = 0; i < boardMembers.length; i++) {
            if (boardMembers[i] == memberToRemove) {
                boardMembers[i] = boardMembers[boardMembers.length - 1];
                boardMembers.pop();
                delete boardMemberDetails[memberToRemove];
                emit BoardMemberRemoved(memberToRemove);
                break;
            }
        }
    }

    // Budget proposal functions

    function createBudgetProposal(string memory description, uint256 amount, uint256 payrollTax) public onlyBoardMember {
        _proposalIds.increment();
        uint256 proposalId = _proposalIds.current();

        proposals[proposalId] = Proposal({
            id: proposalId,
            description: description,
            amount: amount,
            payrollTax: payrollTax,
            deadline: block.timestamp.add(votingDuration),
            approved: false,
            yesVotes: 0,
            noVotes: 0
        });

        emit BudgetProposalCreated(proposalId, description, amount, payrollTax, proposals[proposalId].deadline);
    }

    function voteOnBudgetProposal(uint256 proposalId, bool vote) public {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.deadline, "Voting period has ended");

        if (vote) {
            proposal.yesVotes = proposal.yesVotes.add(token.balanceOf(msg.sender));
        } else {
            proposal.noVotes = proposal.noVotes.add(token.balanceOf(msg.sender));
        }

        emit BudgetProposalVote(proposalId, msg.sender, vote);

        if (proposal.yesVotes > token.totalSupply().mul(50).div(100)) { // 50% approval
            proposal.approved = true;
            emit BudgetProposalApproved(proposalId, proposal.amount, proposal.payrollTax);
        }
    }

    // Utility functions

    function getBoardMembers() public view returns (address[] memory) {
        return boardMembers;
    }

    function isBoardMember(address member) public view returns (bool) {
        return boardMemberDetails[member].member != address(0);
    }

    function getTokenBalance(address account) public view returns (uint256) {
        return token.balanceOf(account);
    }
}
