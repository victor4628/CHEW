// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CHEWRestaurantAccounts_v2.sol"; // We will use the upgraded v2
import "./CHEWToken_v2.sol";           // We will use the upgraded v2

/**
 * @title Crowdsale
 * @notice Sells CHEW tokens (ICO) for mUSDT to fund the DAO treasury.
 * @dev This contract must be granted the MINTER_ROLE on the CHEWToken.
 */
contract Crowdsale is Ownable {
    IERC20 public immutable usdt;
    CHEWToken_v2 public immutable chewToken;
    RestaurantAccounts_v2 public immutable restaurantAccounts;

    uint256 public rate; // How many CHEW tokens per 1 mUSDT (e.g., 1e18 CHEW per 1e6 mUSDT)
    uint256 public usdtRaised;
    bool public saleActive;

    event TokensPurchased(address indexed purchaser, uint256 usdtAmount, uint256 chewAmount);
    event SaleEnded(uint256 totalRaised, uint256 timestamp);

    /**
     * @param _chewToken The CHEWToken (v2) contract
     * @param _usdt The mUSDT token contract
     * @param _restaurantAccounts The RestaurantAccounts (v2) contract
     * @param _rate The amount of CHEW (18 decimals) to sell per 1 mUSDT (6 decimals)
     */
    constructor(
        address _chewToken,
        address _usdt,
        address _restaurantAccounts,
        uint256 _rate
    ) Ownable(msg.sender) {
        require(_chewToken != address(0), "Invalid CHEW address");
        require(_usdt != address(0), "Invalid mUSDT address");
        require(_restaurantAccounts != address(0), "Invalid Accounts address");
        require(_rate > 0, "Rate must be > 0");
        
        chewToken = CHEWToken_v2(_chewToken);
        usdt = IERC20(_usdt);
        restaurantAccounts = RestaurantAccounts_v2(_restaurantAccounts);
        rate = _rate;
        saleActive = true;
    }

    /**
     * @notice Buy CHEW tokens during the ICO.
     * @param usdtAmount The amount of mUSDT to spend (6 decimals).
     */
    function buyTokens(uint256 usdtAmount) external {
        require(saleActive, "Sale is not active");
        require(usdtAmount > 0, "Amount must be > 0");

        // Calculate CHEW amount (adjusting for decimals)
        // (usdtAmount * rate) / 10**6
        uint256 chewAmount = (usdtAmount * rate) / 1e6;
        require(chewAmount > 0, "USDT amount too small");

        // 1. Pull mUSDT from user
        require(usdt.transferFrom(msg.sender, address(this), usdtAmount), "mUSDT transfer failed");

        // 2. Mint CHEW to user
        // *** REQUIRES this contract to have MINTER_ROLE ***
        chewToken.mint(msg.sender, chewAmount);

        usdtRaised += usdtAmount;
        emit TokensPurchased(msg.sender, usdtAmount, chewAmount);
    }

    /**
     * @notice Owner ends the token sale.
     * @dev This transfers all collected mUSDT to the RestaurantAccounts reserve
     * and permanently stops new tokens from being minted.
     */
    function endSale() external onlyOwner {
        require(saleActive, "Sale already ended");
        saleActive = false;

        uint256 balance = usdt.balanceOf(address(this));
        require(balance > 0, "No funds to transfer");

        // 1. Approve RestaurantAccounts to pull the funds
        require(usdt.approve(address(restaurantAccounts), balance), "Approve failed");

        // 2. Call the new function on RestaurantAccounts to fund the reserve
        // *** REQUIRES this contract's owner to also be TREASURER on RestaurantAccounts ***
        // Alternatively, the deployer (as TREASURER) can call this.
        // For simplicity, we assume the DAO Admin (who owns this) will be the one
        // to grant this contract's address the TREASURER_ROLE temporarily
        // or just call the fundReserveWithICOCapital function *from* this contract
        
        // Let's make it simple: The RestaurantAccounts contract's TREASURER
        // will call this function, which then calls the fundReserve function.
        // --- A better pattern ---
        // The owner of this contract calls this, which transfers capital.
        // The owner *must also* have TREASURER_ROLE on RestaurantAccounts.
        restaurantAccounts.fundReserveWithICOCapital(balance);

        // 3. Renounce the Minter role from this contract
        // This is a critical step for decentralization!
        chewToken.renounceRole(chewToken.MINTER_ROLE(), address(this));

        emit SaleEnded(balance, block.timestamp);
    }
}

