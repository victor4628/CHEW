// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CHEWToken
 * @notice CHEW governance token with voting and USDT dividend distribution
 * @dev Uses a points-based system to accurately calculate dividend shares for each token holder
 */
contract CHEWToken is ERC20Votes, AccessControl, Ownable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // ===== Dividend Variables =====
    IERC20 public immutable stable;                          // Stablecoin for dividends (USDT)
    uint256 internal constant POINTS_SCALE = 1e20;           // Precision multiplier

    uint256 public pointsPerToken;                           // Global accumulated dividend points
    mapping(address => int256) internal pointsCorrection;    // Correction value for each address
    mapping(address => uint256) public claimedDividends;     // Total dividends claimed

    // ===== Events =====
    event DividendsDistributed(address indexed distributor, uint256 amount);
    event DividendClaimed(address indexed user, uint256 amount);

    constructor(address stableToken)
        ERC20("CHEW Token", "CHEW")
        EIP712("CHEW Token", "1")
        Ownable(msg.sender)
    {
        require(stableToken != address(0), "Stable token cannot be zero address");
        stable = IERC20(stableToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISTRIBUTOR_ROLE, msg.sender); // Grant distributor role to deployer by default
    }

    // ===== Minting Functions =====
    /**
     * @notice Mint new CHEW tokens
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "Not minter");
        _mint(to, amount);
    }

    // ===== Dividend Functions =====
    /**
     * @notice Distribute USDT dividends to all token holders
     * @param amount Amount of USDT to distribute
     * @dev Only callable by DISTRIBUTOR_ROLE (typically the reserve account contract)
     */
    function distributeDividends(uint256 amount) external {
        require(hasRole(DISTRIBUTOR_ROLE, msg.sender), "Not distributor");
        require(amount > 0, "Amount must be greater than 0");
        require(totalSupply() > 0, "No tokens minted yet");

        // Transfer USDT from caller to this contract
        require(stable.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Update global dividend points: increase dividend points per token
        pointsPerToken += (amount * POINTS_SCALE) / totalSupply();

        emit DividendsDistributed(msg.sender, amount);
    }

    /**
     * @notice Claim dividends for the caller
     * @return Amount of USDT claimed
     */
    function claimDividend() external returns (uint256) {
        uint256 withdrawable = withdrawableDividendOf(msg.sender);
        require(withdrawable > 0, "No dividend to claim");

        claimedDividends[msg.sender] += withdrawable;
        require(stable.transfer(msg.sender, withdrawable), "Transfer failed");

        emit DividendClaimed(msg.sender, withdrawable);
        return withdrawable;
    }

    // ===== Query Functions =====
    /**
     * @notice Query total accumulated dividends for an address (including claimed and unclaimed)
     * @param account Address to query
     */
    function accumulativeDividendOf(address account) public view returns (uint256) {
        uint256 balance = balanceOf(account);
        if (balance == 0) return 0;

        // Accumulated dividend = balance * points per token + correction
        int256 accumulated = int256(balance * pointsPerToken) + pointsCorrection[account];
        
        // If negative after correction, no dividends available
        if (accumulated < 0) return 0;
        
        return uint256(accumulated) / POINTS_SCALE;
    }

    /**
     * @notice Query withdrawable dividends for an address
     * @param account Address to query
     */
    function withdrawableDividendOf(address account) public view returns (uint256) {
        uint256 accumulated = accumulativeDividendOf(account);
        uint256 claimed = claimedDividends[account];
        
        if (accumulated <= claimed) return 0;
        return accumulated - claimed;
    }

    /**
     * @notice Query total dividends already claimed by an address
     * @param account Address to query
     */
    function withdrawnDividendOf(address account) public view returns (uint256) {
        return claimedDividends[account];
    }

    // ===== Internal Functions: Update Dividend Corrections on Transfer =====
    /**
     * @dev Override _update to adjust dividend corrections during token transfers
     * When tokens are transferred, adjust pointsCorrection for sender and receiver
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Votes)
    {
        super._update(from, to, value);

        // Minting: increase receiver's correction (new tokens should not receive past dividends)
        if (from == address(0)) {
            pointsCorrection[to] -= int256(value * pointsPerToken);
        }
        // Burning: decrease sender's correction
        else if (to == address(0)) {
            pointsCorrection[from] += int256(value * pointsPerToken);
        }
        // Transfer: adjust both parties' corrections
        else {
            pointsCorrection[from] += int256(value * pointsPerToken);
            pointsCorrection[to] -= int256(value * pointsPerToken);
        }
    }
}