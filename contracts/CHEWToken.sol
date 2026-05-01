// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CHEWToken (Version 2)
 * @notice Fixes:
 * 1. Removed redundant Ownable (AccessControl is used).
 * 2. Granted MINTER_ROLE and DEFAULT_ADMIN_ROLE to the deployer.
 */
contract CHEWToken is ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // ===== Dividend Variables =====
    IERC20 public immutable stable;
    uint256 internal constant POINTS_SCALE = 1e20;

    uint256 public pointsPerToken;
    mapping(address => int256) internal pointsCorrection;
    mapping(address => uint256) public claimedDividends;

    // ===== Events =====
    event DividendsDistributed(address indexed distributor, uint256 amount);
    event DividendClaimed(address indexed user, uint256 amount);

    constructor(address stableToken)
        ERC20("CHEW Token", "CHEW")
        EIP712("CHEW Token", "1")
    {
        require(stableToken != address(0), "Stable token cannot be zero address");
        stable = IERC20(stableToken);
        
        // --- FIX ---
        // Grant roles to the deployer (msg.sender)
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender); // Now the deployer can grant this to Crowdsale
        _grantRole(DISTRIBUTOR_ROLE, msg.sender);
    }

    // ===== Minting Functions =====
    function mint(address to, uint256 amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "Not minter");
        _mint(to, amount);
    }

    // ===== Dividend Functions =====
    function distributeDividends(uint256 amount) external {
        require(hasRole(DISTRIBUTOR_ROLE, msg.sender), "Not distributor");
        require(amount > 0, "Amount must be greater than 0");
        require(totalSupply() > 0, "No tokens minted yet");

        require(stable.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        pointsPerToken += (amount * POINTS_SCALE) / totalSupply();
        emit DividendsDistributed(msg.sender, amount);
    }

    function claimDividend() external returns (uint256) {
        uint256 withdrawable = withdrawableDividendOf(msg.sender);
        require(withdrawable > 0, "No dividend to claim");

        claimedDividends[msg.sender] += withdrawable;
        require(stable.transfer(msg.sender, withdrawable), "Transfer failed");

        emit DividendClaimed(msg.sender, withdrawable);
        return withdrawable;
    }

    function accumulativeDividendOf(address account) public view returns (uint256) {
        uint256 balance = balanceOf(account);
        if (balance == 0) return 0;
        int256 accumulated = int256(balance * pointsPerToken) + pointsCorrection[account];
        if (accumulated < 0) return 0;
        return uint256(accumulated) / POINTS_SCALE;
    }

    function withdrawableDividendOf(address account) public view returns (uint256) {
        uint256 accumulated = accumulativeDividendOf(account);
        uint256 claimed = claimedDividends[account];
        if (accumulated <= claimed) return 0;
        return accumulated - claimed;
    }

    function withdrawnDividendOf(address account) public view returns (uint256) {
        return claimedDividends[account];
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Votes)
    {
        super._update(from, to, value);
        if (from == address(0)) {
            pointsCorrection[to] -= int256(value * pointsPerToken);
        } else if (to == address(0)) {
            pointsCorrection[from] += int256(value * pointsPerToken);
        } else {
            pointsCorrection[from] += int256(value * pointsPerToken);
            pointsCorrection[to] -= int256(value * pointsPerToken);
        }
    }
}

