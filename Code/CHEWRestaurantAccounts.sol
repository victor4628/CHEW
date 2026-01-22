// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @notice CHEWToken Interface
 */
interface ICHEWToken is IERC20 {
    function distributeDividends(uint256 amount) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/**
 * @title RestaurantAccounts
 * @notice Three-account treasury management system: Receiving/Operating/Reserve
 * @dev Implements fund flows, whitelist payments, flexible spending, and annual dividends
 * 
 * Design Philosophy:
 * - Early Stage: Centralized flexible operations for rapid market response
 * - Mature Stage: Progressive decentralization towards full community governance
 */
contract RestaurantAccounts is AccessControl, ReentrancyGuard {
    
    // ===== Role Definitions =====
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    
    // ===== Contract References =====
    IERC20 public immutable usdt;
    ICHEWToken public immutable chewToken;
    
    // ===== Three Account Balances (Unit: USDT, 6 decimals) =====
    uint256 public receivingBalance;      // Receiving account: customer payment accumulation
    uint256 public operatingBalance;      // Operating account: daily expenses
    uint256 public reserveBalance;        // Reserve account: savings + dividends
    
    // ===== Governable Parameters =====
    uint256 public profitMargin = 70;                   // Profit margin 70%
    uint256 public monthlyRent = 6000e6;                // Monthly rent 6,000 USDT
    uint256 public monthlyUtilities = 1000e6;           // Monthly utilities 1,000 USDT
    uint256 public largeExpenseThreshold = 2000e6;      // Large expense threshold 2,000 USDT
    uint256 public dividendRatio = 80;                  // Dividend ratio 80%
    uint256 public minReserve = 80000e6;                // Minimum reserve 80,000 USDT
    
    // ===== Whitelist Structure =====
    struct Recipient {
        address addr;           // Recipient address
        uint256 amount;         // Amount (monthly)
        bool active;            // Active status
        string description;     // Description
    }
    
    Recipient public landlord;                          // Landlord
    Recipient public utilityProvider;                   // Utility/electricity provider
    mapping(address => Recipient) public employees;     // Employee mapping
    address[] public employeeList;                      // Employee address list
    
    // ===== Expense Records =====
    struct Expense {
        address recipient;      // Recipient
        uint256 amount;         // Amount
        string reason;          // Reason
        uint256 timestamp;      // Timestamp
        address approvedBy;     // Approver
    }
    Expense[] public expenses;
    
    // ===== Settlement Records =====
    uint256 public lastSettlementTime;      // Last settlement time
    uint256 public currentMonth;            // Current month (to prevent duplicate settlements)
    
    // ===== Dividend Records =====
    uint256 public lastDividendTime;        // Last dividend time
    uint256 public totalDividendsDistributed; // Total dividends distributed
    
    // ===== Events =====
    event PaymentReceived(address indexed from, uint256 amount, uint256 timestamp);
    event MonthlySettlement(uint256 toOperating, uint256 toReserve, uint256 timestamp);
    event ExpenseRecorded(address indexed recipient, uint256 amount, string reason);
    event WhitelistUpdated(address indexed recipient, uint256 amount, string role);
    event DividendDistributed(uint256 amount, uint256 timestamp);
    event ParameterUpdated(string param, uint256 newValue);
    event ReserveToOperating(uint256 amount, string reason);
    
    /**
     * @notice Constructor
     * @param _usdt USDT token address
     * @param _chewToken CHEW governance token address
     */
    constructor(address _usdt, address _chewToken) {
        require(_usdt != address(0), "Invalid USDT address");
        require(_chewToken != address(0), "Invalid CHEW address");
        
        usdt = IERC20(_usdt);
        chewToken = ICHEWToken(_chewToken);
        
        // Grant all roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(TREASURER_ROLE, msg.sender);
        
        // Initialize time records
        lastSettlementTime = block.timestamp;
        currentMonth = _getMonth(block.timestamp);
    }
    
    // ========================================
    // Payment Reception
    // ========================================
    
    /**
     * @notice Customer payment (USDT enters receiving account)
     * @param amount Payment amount (note: USDT has 6 decimals)
     */
    function receivePayment(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(usdt.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");
        
        receivingBalance += amount;
        emit PaymentReceived(msg.sender, amount, block.timestamp);
    }
    
    // ========================================
    // Monthly Settlement
    // ========================================
    
    /**
     * @notice End-of-month settlement: allocate receiving account funds to operating and reserve
     * @dev Can only be executed once per month, manually triggered by treasurer
     * 
     * Calculation logic:
     * 1. Operating account = Revenue × (1 - profit margin) + fixed costs
     * 2. Reserve = Revenue - operating allocation
     * 3. If operating account is insufficient, subsidize from reserve
     * 4. Automatically pay all whitelist fixed expenses
     */
    function monthlySettlement() external onlyRole(TREASURER_ROLE) nonReentrant {
        uint256 currentMonthCheck = _getMonth(block.timestamp);
        require(currentMonthCheck > currentMonth, "Already settled this month");
        
        uint256 revenue = receivingBalance;
        require(revenue > 0, "No revenue to settle");
        
        // Calculate cost portion: (1 - profit margin) × revenue
        uint256 costRatio = 100 - profitMargin;
        uint256 costPortion = (revenue * costRatio) / 100;
        
        // Calculate fixed costs: rent + salaries + utilities
        uint256 fixedCosts = monthlyRent + monthlyUtilities + _getTotalSalaries();
        
        // Total amount for operating account
        uint256 toOperating = costPortion + fixedCosts;
        
        // If operating needs exceed revenue, subsidize deficit from reserve
        if (toOperating > revenue) {
            uint256 deficit = toOperating - revenue;
            require(reserveBalance >= deficit, "Insufficient reserve for deficit");
            reserveBalance -= deficit;
            toOperating = revenue;
        }
        
        // Remaining portion goes to reserve
        uint256 toReserve = revenue > toOperating ? revenue - toOperating : 0;
        
        // Update account balances
        receivingBalance = 0;
        operatingBalance += toOperating;
        reserveBalance += toReserve;
        
        // Update time records
        currentMonth = currentMonthCheck;
        lastSettlementTime = block.timestamp;
        
        emit MonthlySettlement(toOperating, toReserve, block.timestamp);
        
        // Automatically pay fixed expenses
        _payFixedExpenses();
    }
    
    /**
     * @notice Automatically pay fixed expenses (rent, salaries, utilities)
     * @dev Internal function, automatically called during monthly settlement
     */
    function _payFixedExpenses() internal {
        // Pay rent
        if (landlord.active && landlord.addr != address(0)) {
            _executePayment(landlord.addr, landlord.amount, "Monthly rent");
        }
        
        // Pay utilities
        if (utilityProvider.active && utilityProvider.addr != address(0)) {
            _executePayment(utilityProvider.addr, utilityProvider.amount, "Monthly utilities");
        }
        
        // Pay all employee salaries
        for (uint256 i = 0; i < employeeList.length; i++) {
            address empAddr = employeeList[i];
            Recipient memory emp = employees[empAddr];
            if (emp.active) {
                _executePayment(emp.addr, emp.amount, string(abi.encodePacked("Salary: ", emp.description)));
            }
        }
    }
    
    // ========================================
    // Flexible Expense Management
    // ========================================
    
    /**
     * @notice Manager initiates expense request
     * @param recipient Recipient address
     * @param amount Amount
     * @param reason Expense reason
     * 
     * @dev Small expenses (< 2000 USDT) are executed directly
     *      Large expenses require governance proposal voting
     */
    function requestExpense(
        address recipient, 
        uint256 amount, 
        string memory reason
    ) 
        external 
        onlyRole(MANAGER_ROLE) 
        nonReentrant 
    {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");
        
        if (amount < largeExpenseThreshold) {
            // Small expense: execute directly
            _executePayment(recipient, amount, reason);
        } else {
            // Large expense: requires proposal (will be enabled after proposal contract is complete)
            revert("Large expense requires governance proposal");
        }
    }
    
    /**
     * @notice Execute approved large expense
     * @dev This function will be called by governance proposal contract in the future
     * @param recipient Recipient
     * @param amount Amount
     * @param reason Reason
     */
    function executeApprovedExpense(
        address recipient, 
        uint256 amount, 
        string memory reason
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        _executePayment(recipient, amount, reason);
    }
    
    /**
     * @notice Internal payment function
     * @dev Deduct from operating account and transfer, record expense
     */
    function _executePayment(
        address recipient, 
        uint256 amount, 
        string memory reason
    ) internal {
        require(operatingBalance >= amount, "Insufficient operating balance");
        
        operatingBalance -= amount;
        require(usdt.transfer(recipient, amount), "USDT transfer failed");
        
        // Record expense
        expenses.push(Expense({
            recipient: recipient,
            amount: amount,
            reason: reason,
            timestamp: block.timestamp,
            approvedBy: msg.sender
        }));
        
        emit ExpenseRecorded(recipient, amount, reason);
    }
    
    // ========================================
    // Reserve Management
    // ========================================
    
    /**
     * @notice Transfer from reserve to operating account
     * @param amount Transfer amount
     * @param reason Reason (e.g., "expansion", "equipment repair", etc.)
     * @dev Requires admin permission (can be changed to proposal approval later)
     */
    function transferReserveToOperating(
        uint256 amount, 
        string memory reason
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(reserveBalance >= amount, "Insufficient reserve balance");
        
        reserveBalance -= amount;
        operatingBalance += amount;
        
        emit ReserveToOperating(amount, reason);
    }
    
    // ========================================
    // Annual Dividends
    // ========================================
    
    /**
     * @notice Year-end dividend distribution to all CHEW holders
     * @dev Anyone can trigger, but only valid in December and once per year
     * 
     * Dividend logic:
     * 1. If 20% of reserve < 80,000 USDT, retain 80,000, distribute remainder
     * 2. Otherwise distribute 80% of reserve
     */
    function distributeDividends() external nonReentrant {
        require(_isYearEnd(), "Not year end (December)");
        require(block.timestamp > lastDividendTime + 360 days, "Already distributed this year");
        
        uint256 reserve = reserveBalance;
        require(reserve > minReserve, "Reserve below minimum threshold");
        
        // Calculate dividend amount
        uint256 dividendAmount;
        uint256 twentyPercent = (reserve * 20) / 100;
        
        if (twentyPercent < minReserve) {
            // Retain minimum reserve, distribute remainder
            dividendAmount = reserve - minReserve;
        } else {
            // Distribute configured ratio (default 80%)
            dividendAmount = (reserve * dividendRatio) / 100;
        }
        
        require(dividendAmount > 0, "No dividend to distribute");
        
        // Deduct dividend amount from reserve
        reserveBalance -= dividendAmount;
        
        // Approve CHEWToken to use USDT
        require(usdt.approve(address(chewToken), dividendAmount), "USDT approve failed");
        
        // Call CHEWToken's dividend function
        chewToken.distributeDividends(dividendAmount);
        
        // Update records
        lastDividendTime = block.timestamp;
        totalDividendsDistributed += dividendAmount;
        
        emit DividendDistributed(dividendAmount, block.timestamp);
    }
    
    // ========================================
    // Whitelist Management
    // ========================================
    
    /**
     * @notice Set landlord information
     */
    function setLandlord(
        address addr, 
        uint256 amount, 
        string memory description
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(addr != address(0), "Invalid address");
        landlord = Recipient(addr, amount, true, description);
        emit WhitelistUpdated(addr, amount, "Landlord");
    }
    
    /**
     * @notice Set utility/electricity provider information
     */
    function setUtilityProvider(
        address addr, 
        uint256 amount, 
        string memory description
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(addr != address(0), "Invalid address");
        utilityProvider = Recipient(addr, amount, true, description);
        emit WhitelistUpdated(addr, amount, "Utility Provider");
    }
    
    /**
     * @notice Add or update employee
     */
    function setEmployee(
        address addr, 
        uint256 salary, 
        string memory name
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(addr != address(0), "Invalid address");
        
        // If new employee, add to list
        if (employees[addr].addr == address(0)) {
            employeeList.push(addr);
        }
        
        employees[addr] = Recipient(addr, salary, true, name);
        emit WhitelistUpdated(addr, salary, string(abi.encodePacked("Employee: ", name)));
    }
    
    /**
     * @notice Remove employee
     */
    function removeEmployee(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(employees[addr].addr != address(0), "Employee does not exist");
        employees[addr].active = false;
        emit WhitelistUpdated(addr, 0, "Employee removed");
    }
    
    // ========================================
    // Parameter Updates (Governable)
    // ========================================
    
    function updateProfitMargin(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newValue <= 100, "Margin cannot exceed 100%");
        profitMargin = newValue;
        emit ParameterUpdated("profitMargin", newValue);
    }
    
    function updateMonthlyRent(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        monthlyRent = newValue;
        emit ParameterUpdated("monthlyRent", newValue);
    }
    
    function updateMonthlyUtilities(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        monthlyUtilities = newValue;
        emit ParameterUpdated("monthlyUtilities", newValue);
    }
    
    function updateLargeExpenseThreshold(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        largeExpenseThreshold = newValue;
        emit ParameterUpdated("largeExpenseThreshold", newValue);
    }
    
    function updateDividendRatio(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newValue <= 100, "Ratio cannot exceed 100%");
        dividendRatio = newValue;
        emit ParameterUpdated("dividendRatio", newValue);
    }
    
    function updateMinReserve(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minReserve = newValue;
        emit ParameterUpdated("minReserve", newValue);
    }
    
    // ========================================
    // Query Functions
    // ========================================
    
    /**
     * @notice Get total balance of three accounts
     */
    function getTotalBalance() external view returns (uint256) {
        return receivingBalance + operatingBalance + reserveBalance;
    }
    
    /**
     * @notice Get total number of expense records
     */
    function getExpenseCount() external view returns (uint256) {
        return expenses.length;
    }
    
    /**
     * @notice Get total number of employees
     */
    function getEmployeeCount() external view returns (uint256) {
        return employeeList.length;
    }
    
    /**
     * @notice Get specific expense record
     */
    function getExpense(uint256 index) external view returns (
        address recipient,
        uint256 amount,
        string memory reason,
        uint256 timestamp,
        address approvedBy
    ) {
        require(index < expenses.length, "Index out of bounds");
        Expense memory exp = expenses[index];
        return (exp.recipient, exp.amount, exp.reason, exp.timestamp, exp.approvedBy);
    }
    
    /**
     * @notice Get all employee addresses
     */
    function getAllEmployees() external view returns (address[] memory) {
        return employeeList;
    }
    
    /**
     * @notice Calculate total monthly salaries
     */
    function _getTotalSalaries() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < employeeList.length; i++) {
            if (employees[employeeList[i]].active) {
                total += employees[employeeList[i]].amount;
            }
        }
        return total;
    }
    
    /**
     * @notice Get current month number (simplified calculation)
     */
    function _getMonth(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / 30 days;
    }
    
    /**
     * @notice Check if it's year-end (December)
     * @dev Simplified version: checks if between Dec 1 - Dec 31
     *      Production environment should use BokkyPooBahsDateTimeLibrary
     */
    function _isYearEnd() internal view returns (bool) {
        uint256 dayOfYear = (block.timestamp / 1 days) % 365;
        return dayOfYear >= 334 && dayOfYear <= 365;
    }
    
    // ========================================
    // Emergency Functions
    // ========================================
    
    /**
     * @notice Emergency withdrawal (admin only)
     * @dev For extreme situations requiring fund rescue
     */
    function emergencyWithdraw(address token, uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }
}