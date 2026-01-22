// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MenuVoting
 * @notice Restaurant menu quarterly voting system
 * @dev CHEW holders can submit candidate dishes and vote, selecting top 20 dishes each quarter
 * 
 * Voting Rules:
 * - Anyone can submit candidate dishes
 * - Voting weight based on CHEW balance at snapshot (prevents flash loan attacks)
 * - One address can vote for multiple dishes, each receiving the address's full weight
 * - Voting occurs quarterly (3 months)
 * - Automatically selects top 20 dishes
 */
contract MenuVoting is AccessControl, ReentrancyGuard {
    
    // ===== Constants =====
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public constant MAX_MENU_SIZE = 20;         // Maximum 20 dishes on menu
    uint256 public constant VOTING_PERIOD = 90 days;    // Voting period: 3 months
    uint256 public constant SNAPSHOT_DELAY = 1 days;    // Snapshot delay (1 day before voting)
    
    // ===== Contract References =====
    IVotes public immutable chewToken;
    
    // ===== Dish Structure =====
    struct Dish {
        uint256 id;                 // Dish ID
        string name;                // Dish name
        string description;         // Description
        address submitter;          // Submitter
        uint256 totalVotes;         // Total votes
        uint256 submitTime;         // Submission time
        bool isActive;              // Whether active as candidate
    }
    
    // ===== Voting Season Information =====
    struct VotingSeason {
        uint256 seasonNumber;       // Season number
        uint256 startTime;          // Start time
        uint256 endTime;            // End time
        uint256 snapshotBlock;      // Snapshot block (for determining voting weight)
        bool isFinalized;           // Whether finalized
        uint256[] topDishIds;       // Top 20 dish IDs selected
    }
    
    // ===== State Variables =====
    uint256 public currentSeasonNumber;                             // Current season number
    uint256 public nextDishId = 1;                                  // Next dish ID
    
    mapping(uint256 => Dish) public dishes;                         // Dish ID => Dish info
    uint256[] public allDishIds;                                    // All dish ID list
    
    mapping(uint256 => VotingSeason) public seasons;                // Season number => Season info
    mapping(uint256 => mapping(uint256 => uint256)) public seasonDishVotes;  // Season => DishID => Votes
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) public hasVoted; // Season => Address => DishID => HasVoted
    
    uint256[] public currentMenu;                                   // Current menu (dish IDs)
    
    // ===== Events =====
    event DishSubmitted(uint256 indexed dishId, string name, address indexed submitter, uint256 timestamp);
    event VoteCast(uint256 indexed seasonNumber, uint256 indexed dishId, address indexed voter, uint256 weight);
    event SeasonFinalized(uint256 indexed seasonNumber, uint256[] topDishIds, uint256 timestamp);
    event NewSeasonStarted(uint256 indexed seasonNumber, uint256 startTime, uint256 endTime);
    
    /**
     * @notice Constructor
     * @param _chewToken CHEW token address
     */
    constructor(address _chewToken) {
        require(_chewToken != address(0), "Invalid CHEW token address");
        chewToken = IVotes(_chewToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        
        // Start first voting season
        _startNewSeason();
    }
    
    // ========================================
    // Dish Submission
    // ========================================
    
    /**
     * @notice Submit candidate dish
     * @param name Dish name
     * @param description Description
     */
    function submitDish(string memory name, string memory description) external nonReentrant {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(name).length <= 100, "Name too long");
        require(bytes(description).length <= 500, "Description too long");
        
        uint256 dishId = nextDishId++;
        
        dishes[dishId] = Dish({
            id: dishId,
            name: name,
            description: description,
            submitter: msg.sender,
            totalVotes: 0,
            submitTime: block.timestamp,
            isActive: true
        });
        
        allDishIds.push(dishId);
        
        emit DishSubmitted(dishId, name, msg.sender, block.timestamp);
    }
    
    /**
     * @notice Manager removes inappropriate dish
     * @param dishId Dish ID
     */
    function removeDish(uint256 dishId) external onlyRole(MANAGER_ROLE) {
        require(dishes[dishId].id != 0, "Dish does not exist");
        dishes[dishId].isActive = false;
    }
    
    // ========================================
    // Voting Functions
    // ========================================
    
    /**
     * @notice Vote for a dish
     * @param dishId Dish ID
     * @dev Voting weight based on CHEW balance at snapshot block (prevents flash loans and double voting)
     *      One address can vote for multiple dishes
     */
    function vote(uint256 dishId) external nonReentrant {
        require(dishes[dishId].id != 0, "Dish does not exist");
        require(dishes[dishId].isActive, "Dish is not active");
        require(_isVotingActive(), "Voting period not active");
        require(!hasVoted[currentSeasonNumber][msg.sender][dishId], "Already voted for this dish");
        
        // Use snapshot block voting weight
        uint256 snapshotBlock = seasons[currentSeasonNumber].snapshotBlock;
        uint256 weight = chewToken.getPastVotes(msg.sender, snapshotBlock);
        require(weight > 0, "No voting power at snapshot block");
        
        // Record vote
        seasonDishVotes[currentSeasonNumber][dishId] += weight;
        hasVoted[currentSeasonNumber][msg.sender][dishId] = true;
        
        emit VoteCast(currentSeasonNumber, dishId, msg.sender, weight);
    }
    
    /**
     * @notice Batch vote (vote for multiple dishes at once)
     * @param dishIds Array of dish IDs
     */
    function voteBatch(uint256[] memory dishIds) external nonReentrant {
        require(_isVotingActive(), "Voting period not active");
        require(dishIds.length > 0 && dishIds.length <= 50, "Invalid batch size");
        
        // Use snapshot block voting weight
        uint256 snapshotBlock = seasons[currentSeasonNumber].snapshotBlock;
        uint256 weight = chewToken.getPastVotes(msg.sender, snapshotBlock);
        require(weight > 0, "No voting power at snapshot block");
        
        for (uint256 i = 0; i < dishIds.length; i++) {
            uint256 dishId = dishIds[i];
            
            require(dishes[dishId].id != 0, "Dish does not exist");
            require(dishes[dishId].isActive, "Dish is not active");
            require(!hasVoted[currentSeasonNumber][msg.sender][dishId], "Already voted for this dish");
            
            seasonDishVotes[currentSeasonNumber][dishId] += weight;
            hasVoted[currentSeasonNumber][msg.sender][dishId] = true;
            
            emit VoteCast(currentSeasonNumber, dishId, msg.sender, weight);
        }
    }
    
    // ========================================
    // Season Finalization
    // ========================================
    
    /**
     * @notice Finalize current season voting, select top 20 dishes
     * @dev Can only be called after voting period ends
     */
    function finalizeSeason() external nonReentrant {
        require(!seasons[currentSeasonNumber].isFinalized, "Season already finalized");
        require(block.timestamp >= seasons[currentSeasonNumber].endTime, "Voting period not ended");
        
        // Get all active dishes' votes
        uint256[] memory validDishIds = _getActiveDishIds();
        require(validDishIds.length > 0, "No dishes to finalize");
        
        // Sort and select top 20
        uint256[] memory topDishes = _getTopDishes(validDishIds, MAX_MENU_SIZE);
        
        // Update current menu
        currentMenu = topDishes;
        seasons[currentSeasonNumber].topDishIds = topDishes;
        seasons[currentSeasonNumber].isFinalized = true;
        
        emit SeasonFinalized(currentSeasonNumber, topDishes, block.timestamp);
        
        // Start new voting season
        _startNewSeason();
    }
    
    /**
     * @notice Start new voting season
     * @dev Set snapshot block to current block (voting effective from next block)
     */
    function _startNewSeason() internal {
        currentSeasonNumber++;
        
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + VOTING_PERIOD;
        uint256 snapshotBlock = block.number; // Use current block as snapshot
        
        seasons[currentSeasonNumber] = VotingSeason({
            seasonNumber: currentSeasonNumber,
            startTime: startTime,
            endTime: endTime,
            snapshotBlock: snapshotBlock,
            isFinalized: false,
            topDishIds: new uint256[](0)
        });
        
        emit NewSeasonStarted(currentSeasonNumber, startTime, endTime);
    }
    
    /**
     * @notice Get all active dish IDs
     */
    function _getActiveDishIds() internal view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Count first
        for (uint256 i = 0; i < allDishIds.length; i++) {
            if (dishes[allDishIds[i]].isActive) {
                activeCount++;
            }
        }
        
        // Build array
        uint256[] memory activeDishes = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allDishIds.length; i++) {
            if (dishes[allDishIds[i]].isActive) {
                activeDishes[index] = allDishIds[i];
                index++;
            }
        }
        
        return activeDishes;
    }
    
    /**
     * @notice Select top N dishes by votes (simple bubble sort)
     * @dev Production environments should use more efficient sorting or off-chain calculation
     */
    function _getTopDishes(uint256[] memory dishIds, uint256 topN) internal view returns (uint256[] memory) {
        uint256 length = dishIds.length;
        if (length == 0) return new uint256[](0);
        
        // Limit result size
        uint256 resultSize = length < topN ? length : topN;
        
        // Copy array for sorting
        uint256[] memory sortedIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            sortedIds[i] = dishIds[i];
        }
        
        // Bubble sort (descending by votes)
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                uint256 votes1 = seasonDishVotes[currentSeasonNumber][sortedIds[j]];
                uint256 votes2 = seasonDishVotes[currentSeasonNumber][sortedIds[j + 1]];
                
                if (votes1 < votes2) {
                    uint256 temp = sortedIds[j];
                    sortedIds[j] = sortedIds[j + 1];
                    sortedIds[j + 1] = temp;
                }
            }
        }
        
        // Return top N
        uint256[] memory topDishes = new uint256[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            topDishes[i] = sortedIds[i];
        }
        
        return topDishes;
    }
    
    // ========================================
    // Query Functions
    // ========================================
    
    /**
     * @notice Check if currently in voting period
     */
    function _isVotingActive() internal view returns (bool) {
        VotingSeason memory season = seasons[currentSeasonNumber];
        return !season.isFinalized && block.timestamp < season.endTime;
    }
    
    /**
     * @notice Query current voting period status
     */
    function isVotingActive() external view returns (bool) {
        return _isVotingActive();
    }
    
    /**
     * @notice Query remaining time in current season
     */
    function getRemainingTime() external view returns (uint256) {
        if (!_isVotingActive()) return 0;
        return seasons[currentSeasonNumber].endTime - block.timestamp;
    }
    
    /**
     * @notice Get current menu (20 dishes on menu)
     */
    function getCurrentMenu() external view returns (uint256[] memory) {
        return currentMenu;
    }
    
    /**
     * @notice Get current menu detailed information
     */
    function getCurrentMenuDetails() external view returns (Dish[] memory) {
        Dish[] memory menuDishes = new Dish[](currentMenu.length);
        for (uint256 i = 0; i < currentMenu.length; i++) {
            menuDishes[i] = dishes[currentMenu[i]];
        }
        return menuDishes;
    }
    
    /**
     * @notice Get dish votes in current season
     */
    function getDishVotes(uint256 dishId) external view returns (uint256) {
        return seasonDishVotes[currentSeasonNumber][dishId];
    }
    
    /**
     * @notice Get total number of candidate dishes
     */
    function getTotalDishCount() external view returns (uint256) {
        return allDishIds.length;
    }
    
    /**
     * @notice Batch get dish information
     * @param startIndex Start index
     * @param count Count
     */
    function getDishes(uint256 startIndex, uint256 count) external view returns (Dish[] memory) {
        require(startIndex < allDishIds.length, "Start index out of bounds");
        
        uint256 endIndex = startIndex + count;
        if (endIndex > allDishIds.length) {
            endIndex = allDishIds.length;
        }
        
        uint256 resultCount = endIndex - startIndex;
        Dish[] memory result = new Dish[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = dishes[allDishIds[startIndex + i]];
        }
        
        return result;
    }
    
    /**
     * @notice Query voting power for an address in current season
     * @param account Address to query
     */
    function getVotingPower(address account) external view returns (uint256) {
        if (!_isVotingActive()) return 0;
        uint256 snapshotBlock = seasons[currentSeasonNumber].snapshotBlock;
        return chewToken.getPastVotes(account, snapshotBlock);
    }
    
    /**
     * @notice Get current season's snapshot block number
     */
    function getCurrentSnapshotBlock() external view returns (uint256) {
        return seasons[currentSeasonNumber].snapshotBlock;
    }
    
    /**
     * @notice Check if an address has voted for a specific dish
     */
    function hasVotedFor(address voter, uint256 dishId) external view returns (bool) {
        return hasVoted[currentSeasonNumber][voter][dishId];
    }
    
    /**
     * @notice Get historical season's winning menu
     */
    function getSeasonMenu(uint256 seasonNumber) external view returns (uint256[] memory) {
        require(seasons[seasonNumber].isFinalized, "Season not finalized");
        return seasons[seasonNumber].topDishIds;
    }
}