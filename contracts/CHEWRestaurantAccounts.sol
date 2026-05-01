// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICHEWToken is IERC20 {
    function distributeDividends(uint256 amount) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/**
 * @title RestaurantAccounts (Version 2)
 * @notice Adds one crucial function: `fundReserveWithICOCapital`
 */
contract RestaurantAccounts is AccessControl, ReentrancyGuard {
    
    // ===== Role Definitions =====
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    
    // ===== Contract References =====
    IERC20 public immutable usdt;
    ICHEWToken public immutable chewToken;
    
    uint256 public receivingBalance;
    uint256 public operatingBalance;
    uint256 public reserveBalance;
    
    uint256 public profitMargin = 70;
    uint256 public monthlyRent = 6000e6;
    uint256 public monthlyUtilities = 1000e6;
    uint256 public largeExpenseThreshold = 2000e6;
    uint256 public dividendRatio = 80;
    uint256 public minReserve = 80000e6;
    
    struct Recipient { address addr; uint256 amount; bool active; string description; }
    Recipient public landlord;
    Recipient public utilityProvider;
    mapping(address => Recipient) public employees;
    address[] public employeeList;
    struct Expense { address recipient; uint256 amount; string reason; uint256 timestamp; address approvedBy; }
    Expense[] public expenses;
    uint256 public lastSettlementTime;
    uint256 public currentMonth;
    uint256 public lastDividendTime;
    uint256 public totalDividendsDistributed;
    
    event PaymentReceived(address indexed from, uint256 amount, uint256 timestamp);
    event MonthlySettlement(uint256 toOperating, uint256 toReserve, uint256 timestamp);
    event ExpenseRecorded(address indexed recipient, uint256 amount, string reason);
    event WhitelistUpdated(address indexed recipient, uint256 amount, string role);
    event DividendDistributed(uint256 amount, uint256 timestamp);
    event ParameterUpdated(string param, uint256 newValue);
    event ReserveToOperating(uint256 amount, string reason);
    
    // ===== NEW EVENT =====
    event ICOFundsReceived(address indexed from, uint256 amount);

    constructor(address _usdt, address _chewToken) {
        require(_usdt != address(0), "Invalid USDT address");
        require(_chewToken != address(0), "Invalid CHEW address");
        
        usdt = IERC20(_usdt);
        chewToken = ICHEWToken(_chewToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(TREASURER_ROLE, msg.sender);
        
        lastSettlementTime = block.timestamp;
        currentMonth = _getMonth(block.timestamp);
    }
    
    /**
     * @notice Receives the ICO capital from the Crowdsale contract.
     * @dev This is called by the Crowdsale contract owner (or the contract itself).
     * It MUST be called by an account with TREASURER_ROLE.
     * The caller must first `approve` this contract to spend the mUSDT.
     * @param amount The total mUSDT raised from the ICO.
     */
    function fundReserveWithICOCapital(uint256 amount) external onlyRole(TREASURER_ROLE) nonReentrant {
        require(amount > 0, "Amount must be > 0");
        
        // Pull funds from the caller (which should be the Crowdsale contract)
        require(usdt.transferFrom(msg.sender, address(this), amount), "mUSDT transfer failed");
        
        // Add funds DIRECTLY to reserve, bypassing receiving/operating accounts
        reserveBalance += amount;
        
        emit ICOFundsReceived(msg.sender, amount);
    }

    function receivePayment(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(usdt.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");
        receivingBalance += amount;
        emit PaymentReceived(msg.sender, amount, block.timestamp);
    }
    
    function monthlySettlement() external onlyRole(TREASURER_ROLE) nonReentrant {
        uint256 currentMonthCheck = _getMonth(block.timestamp);
        require(currentMonthCheck > currentMonth, "Already settled this month");
        uint256 revenue = receivingBalance;
        require(revenue > 0, "No revenue to settle");
        uint256 costRatio = 100 - profitMargin;
        uint256 costPortion = (revenue * costRatio) / 100;
        uint256 fixedCosts = monthlyRent + monthlyUtilities + _getTotalSalaries();
        uint256 toOperating = costPortion + fixedCosts;
        if (toOperating > revenue) {
            uint256 deficit = toOperating - revenue;
            require(reserveBalance >= deficit, "Insufficient reserve for deficit");
            reserveBalance -= deficit;
            toOperating = revenue;
        }
        uint256 toReserve = revenue > toOperating ? revenue - toOperating : 0;
        receivingBalance = 0;
        operatingBalance += toOperating;
        reserveBalance += toReserve;
        currentMonth = currentMonthCheck;
        lastSettlementTime = block.timestamp;
        emit MonthlySettlement(toOperating, toReserve, block.timestamp);
        _payFixedExpenses();
    }
    
    function _payFixedExpenses() internal {
        if (landlord.active && landlord.addr != address(0)) {
            _executePayment(landlord.addr, landlord.amount, "Monthly rent");
        }
        if (utilityProvider.active && utilityProvider.addr != address(0)) {
            _executePayment(utilityProvider.addr, utilityProvider.amount, "Monthly utilities");
        }
        for (uint256 i = 0; i < employeeList.length; i++) {
            address empAddr = employeeList[i];
            Recipient memory emp = employees[empAddr];
            if (emp.active) {
                _executePayment(emp.addr, emp.amount, string(abi.encodePacked("Salary: ", emp.description)));
            }
        }
    }
    
    function requestExpense(address recipient, uint256 amount, string memory reason) external onlyRole(MANAGER_ROLE) nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");
        if (amount < largeExpenseThreshold) {
            _executePayment(recipient, amount, reason);
        } else {
            revert("Large expense requires governance proposal");
        }
    }
    
    function executeApprovedExpense(address recipient, uint256 amount, string memory reason) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        _executePayment(recipient, amount, reason);
    }
    
    function _executePayment(address recipient, uint256 amount, string memory reason) internal {
        require(operatingBalance >= amount, "Insufficient operating balance");
        operatingBalance -= amount;
        require(usdt.transfer(recipient, amount), "USDT transfer failed");
        expenses.push(Expense({ recipient: recipient, amount: amount, reason: reason, timestamp: block.timestamp, approvedBy: msg.sender }));
        emit ExpenseRecorded(recipient, amount, reason);
    }
    
    function transferReserveToOperating(uint256 amount, string memory reason) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(reserveBalance >= amount, "Insufficient reserve balance");
        reserveBalance -= amount;
        operatingBalance += amount;
        emit ReserveToOperating(amount, reason);
    }
    
    function distributeDividends() external nonReentrant {
        require(_isYearEnd(), "Not year end (December)");
        require(block.timestamp > lastDividendTime + 360 days, "Already distributed this year");
        uint256 reserve = reserveBalance;
        require(reserve > minReserve, "Reserve below minimum threshold");
        uint256 dividendAmount;
        uint256 twentyPercent = (reserve * 20) / 100;
        if (twentyPercent < minReserve) {
            dividendAmount = reserve - minReserve;
        } else {
            dividendAmount = (reserve * dividendRatio) / 100;
        }
        require(dividendAmount > 0, "No dividend to distribute");
        reserveBalance -= dividendAmount;
        require(usdt.approve(address(chewToken), dividendAmount), "USDT approve failed");
        chewToken.distributeDividends(dividendAmount);
        lastDividendTime = block.timestamp;
        totalDividendsDistributed += dividendAmount;
        emit DividendDistributed(dividendAmount, block.timestamp);
    }
    
    function setLandlord(address addr, uint256 amount, string memory description) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(addr != address(0), "Invalid address");
        landlord = Recipient(addr, amount, true, description);
        emit WhitelistUpdated(addr, amount, "Landlord");
    }
    
    function setUtilityProvider(address addr, uint256 amount, string memory description) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(addr != address(0), "Invalid address");
        utilityProvider = Recipient(addr, amount, true, description);
        emit WhitelistUpdated(addr, amount, "Utility Provider");
    }
    
    function setEmployee(address addr, uint256 salary, string memory name) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(addr != address(0), "Invalid address");
        if (employees[addr].addr == address(0)) {
            employeeList.push(addr);
        }
        employees[addr] = Recipient(addr, salary, true, name);
        emit WhitelistUpdated(addr, salary, string(abi.encodePacked("Employee: ", name)));
    }
    
    function removeEmployee(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(employees[addr].addr != address(0), "Employee does not exist");
        employees[addr].active = false;
        emit WhitelistUpdated(addr, 0, "Employee removed");
    }
    
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
    
    function getTotalBalance() external view returns (uint256) {
        return receivingBalance + operatingBalance + reserveBalance;
    }
    
    function getExpenseCount() external view returns (uint256) {
        return expenses.length;
    }
    
    function getEmployeeCount() external view returns (uint256) {
        return employeeList.length;
    }
    
    function getExpense(uint256 index) external view returns (address recipient, uint256 amount, string memory reason, uint256 timestamp, address approvedBy) {
        require(index < expenses.length, "Index out of bounds");
        Expense memory exp = expenses[index];
        return (exp.recipient, exp.amount, exp.reason, exp.timestamp, exp.approvedBy);
    }
    
    function getAllEmployees() external view returns (address[] memory) {
        return employeeList;
    }
    
    function _getTotalSalaries() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < employeeList.length; i++) {
            if (employees[employeeList[i]].active) {
                total += employees[employeeList[i]].amount;
            }
        }
        return total;
    }
    
    function _getMonth(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / 30 days;
    }
    
    function _isYearEnd() internal view returns (bool) {
        uint256 dayOfYear = (block.timestamp / 1 days) % 365;
        return dayOfYear >= 334 && dayOfYear <= 365;
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }
}
