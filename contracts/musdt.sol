// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDT
 * @notice Test stablecoin with 6 decimals, simulating real USDT
 * @dev For testing environments only, use real USDT on mainnet
 */
contract MockUSDT is ERC20Permit, Ownable {
    constructor()
        ERC20("Mock USDT", "mUSDT")
        ERC20Permit("Mock USDT")
        Ownable(msg.sender)
    {
        // Mint 1,000,000 mUSDT to deployer initially
        _mint(msg.sender, 1_000_000e6);
    }

    /**
     * @notice Returns 6 decimals (consistent with real USDT)
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Owner can mint additional tokens (for testing only)
     * @param to Recipient address
     * @param amount Amount to mint (note: 6 decimal places)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Convenience function: send USDT to specified address (for testing)
     * @param to Recipient address
     * @param amountInDollars Dollar amount (automatically converted to 6 decimals)
     */
    function mintDollars(address to, uint256 amountInDollars) external onlyOwner {
        _mint(to, amountInDollars * 1e6);
    }
}