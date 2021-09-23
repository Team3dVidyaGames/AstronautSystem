// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IInventory.sol";
import "./interfaces/IDarkMatter.sol";

/**
 * @title Astronaut Contract
 */
contract Astronaut is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Event emitted only on construction.
    event AstronautDeployed();

    /// @notice Event emitted when astronaut created.
    event AstronautCreated(
        address user,
        string name,
        uint256 skill,
        uint256 tokenId,
        uint256 amount
    );

    /// @notice Event emitted when tank added.
    event TanksAdded(
        address user,
        uint256 timeTillDeath,
        uint256 tokenId,
        uint256 amount,
        uint256 skill
    );

    /// @notice Event emitted when dark matter collected.
    event DarkMatterCollected(address user, uint256 darkMatter);

    /// @notice Event emitted when max level acheived.
    event maxLevelAcheived(uint256 skill, uint256 maxLevel);

    /// @notice Event emitted when astronaut rescued.
    event AstronautRescued(
        address user,
        uint256 tokenId,
        uint256 amount,
        uint256 timeTillDeath
    );

    /// @notice Event emitted when dark matter bonus is gotten.
    event GotDarkMatterBonus(
        address user,
        uint256 tokenId,
        uint256 amount,
        uint256 darkMatterBonus
    );

    /// @notice Event emitted when dark matter bonus is removed.
    event DarkMatterBonusRemoved(
        address user,
        uint256 removeBonus,
        uint256 darkMatterBonus
    );

    /// @notice Event emitted when astronaut is trained.
    event AstronautTrained(address user, uint256 skill, uint256 experience);

    /// @notice Event emitted when the astronaut name is changed.
    event NameChanged(string newName);

    /// @notice Event emitted when the tank duration is changed.
    event TankDurationChanged(uint256 duration);

    /// @notice Event emitted when the tank cost is changed.
    event TankCostChanged(uint256 tankCost);

    /// @notice Event emitted when the max dark matter tank is changed.
    event TankRateChanged(uint256 newMaxDarkMatterTank);

    /// @notice Event emitted when the level is updated.
    event LevelUpdated(bool updated, uint256 level);

    IERC20 Vidya;
    IDarkMatter DarkMatter;
    IInventory Inventory;

    address public vaultAddr;
    address public devAddr;

    uint256 public constant fee = 5 * 10**18;
    uint256 public constant darkMatterDeci = 10**18;
    uint256 public constant expToBuy = 5 * 10**17;

    uint256 public constant darkMatterId = 18;
    uint256 public constant tankId = 36;
    uint256 public constant maxLevel = 99;

    uint256 public maxDarkMatterTank;
    uint256 public tankDuration;
    uint256 public costOfTank;
    uint256[] public levels;

    struct Astronauts {
        string name;
        uint256[3] multiplier; //speed, harvest, oxygen_equipmet
        uint256[3] level;
        uint256[3] experience;
        uint256 timeTillDeath;
        uint256 darkMatterCollectionRate;
        uint256 lastCollected;
        bool created;
        uint256 darkMatterBonus;
    }

    mapping(address => Astronauts) public players;

    modifier notDeadYet() {
        require(
            players[msg.sender].timeTillDeath >= block.timestamp,
            "Astronaut: Astronaut lost in Space."
        );
        _;
    }

    modifier aloneInSpace() {
        require(
            players[msg.sender].timeTillDeath < block.timestamp,
            "Astronaut: Still in contact with SpaceMan"
        );
        _;
    }

    /**
     * @dev Constructor function
     * @param _devAddr Developer Address
     * @param _vaultAddr Vault Address
     * @param _Vidya Interface of Vidya (0x3D3D35bb9bEC23b06Ca00fe472b50E7A4c692C30)
     * @param _DarkMatter Interface of Dark Matter
     * @param _Inventory Interface of Inventory
     */
    constructor(
        address _devAddr,
        address _vaultAddr,
        IERC20 _Vidya,
        IDarkMatter _DarkMatter,
        IInventory _Inventory
    ) {
        devAddr = _devAddr;
        Inventory = _Inventory;
        Vidya = _Vidya;
        DarkMatter = _DarkMatter;
        vaultAddr = _vaultAddr;

        levels.push(1 * darkMatterDeci); //0-1
        levels.push(3 * darkMatterDeci); //1-2
        levels.push(6 * darkMatterDeci); //2-3
        levels.push(10 * darkMatterDeci); //3-4
        levels.push(15 * darkMatterDeci); //4-5
        levels.push(21 * darkMatterDeci); //5-6

        emit AstronautDeployed();
    }

    /**
     * @dev External function to create Astronaut.
     * @param _name Astronaut Name
     * @param _skill Skill attribution
     * @param _amount Tank amount
     */
    function createAstronaut(
        string memory _name,
        uint256 _skill,
        uint256 _amount
    ) external {
        require(
            !players[msg.sender].created,
            "Astronaut: There can only be one"
        );

        require(_amount <= 15, "Astronaut: Too many tanks");

        Inventory.burn(msg.sender, tankId, _amount);

        Astronauts memory holder;

        holder.name = _name;
        holder.multiplier[_skill] = 95;
        holder.multiplier[(_skill + 1) % 3] = 100;
        holder.multiplier[(_skill + 2) % 3] = 100;
        holder.level[_skill] = 5;
        holder.timeTillDeath = block.timestamp + (tankDuration * _amount);
        holder.lastCollected = block.timestamp;
        holder.darkMatterCollectionRate = DMCollectionRate(100, 100, 95);
        holder.darkMatterBonus = 100;
        holder.created = true;

        players[msg.sender] = holder;

        emit AstronautCreated(msg.sender, _name, _skill, tankId, _amount);
    }

    /**
     * @dev External function to add tanks.
     * @param _amount Tank amount
     * @param _skill Skill attribution
     */
    function addTanks(uint256 _amount, uint256 _skill) external notDeadYet {
        require(_amount <= 15, "Astronaut: Too many tanks");

        Inventory.burn(msg.sender, tankId, _amount);

        collectDarkMatter(_skill);

        uint256 time = tankDuration * _amount;

        players[msg.sender].timeTillDeath += time;

        emit TanksAdded(
            msg.sender,
            players[msg.sender].timeTillDeath,
            tankId,
            _amount,
            _skill
        );
    }

    /**
     * @dev External function to collect dark matter.
     * @param _skill Skill attribution
     */
    function harvestDarkMatter(uint256 _skill)
        external
        notDeadYet
        nonReentrant
    {
        collectDarkMatter(_skill);
    }

    /**
     * @dev Internal function to collect dark matter.
     * @param _skill Skill attribution
     */
    function collectDarkMatter(uint256 _skill) internal {
        Astronauts storage user = players[msg.sender];

        uint256 darkMatter = (user.darkMatterBonus *
            (block.timestamp - user.lastCollected) *
            user.darkMatterCollectionRate) / 100;

        user.lastCollected = block.timestamp;
        user.experience[_skill] += darkMatter;

        uint256 level = user.level[_skill];

        if (level < maxLevel) {
            if (user.experience[_skill] >= levels[level]) {
                user.level[_skill] = level + 1;
                user.experience[_skill] -= levels[level];
                user.multiplier[_skill] -= 1;
                nextLevel(level);
            }
        } else {
            emit maxLevelAcheived(_skill, maxLevel);
        }

        user.darkMatterCollectionRate = DMCollectionRate(
            user.multiplier[0],
            user.multiplier[1],
            user.multiplier[2]
        );

        DarkMatter.mint(msg.sender, darkMatter); //mint dark matter

        emit DarkMatterCollected(msg.sender, darkMatter);
    }

    /**
     * @dev External function to rescue astronaut. This function can be called by only astronuat hasn't got any O2 tanks.
     * @param _amount Tank amount
     */
    function rescueAstronaut(uint256 _amount)
        external
        aloneInSpace
        nonReentrant
    {
        require(
            !players[msg.sender].created,
            "Astronaut: There can only be one."
        );

        require(_amount <= 15, "Astronaut: Too many tanks");

        Vidya.safeTransferFrom(msg.sender, vaultAddr, fee);

        Inventory.burn(msg.sender, tankId, _amount);

        Astronauts storage user = players[msg.sender];

        for (uint256 i = 0; i < 3; i++) {
            uint256 level = user.level[i];
            if (level % 2 == 1) {
                level += 1;
            }
            level = level / 2;
            user.level[i] = level;
            user.multiplier[i] = 100 - level;
            user.experience[i] = 0;
        }

        user.lastCollected = block.timestamp;

        user.darkMatterCollectionRate = DMCollectionRate(
            user.multiplier[0],
            user.multiplier[1],
            user.multiplier[2]
        );

        user.timeTillDeath = block.timestamp + (_amount * tankDuration);

        emit AstronautRescued(msg.sender, tankId, _amount, user.timeTillDeath);
    }

    /**
     * @dev External function for dark matter bonus.
     * @param _amount DarkMatter amount
     * @param _skill Skill attribution
     */
    function darkMatterNFTBonus(uint256 _amount, uint256 _skill)
        external
        nonReentrant
    {
        require(_amount <= 15, "Astronaut: Too much Dark Matter at once.");

        Inventory.burn(msg.sender, darkMatterId, _amount);

        players[msg.sender].darkMatterBonus += (2 * _amount);

        collectDarkMatter(_skill);

        emit GotDarkMatterBonus(
            msg.sender,
            darkMatterId,
            _amount,
            players[msg.sender].darkMatterBonus
        );
    }

    /**
     * @dev External function to remove dark matter bonus.
     * @param _amount DarkMatter amount
     */
    function removeDarkMatterBonus(uint256 _amount) external nonReentrant {
        Astronauts storage user = players[msg.sender];
        uint256 nftOwned = user.darkMatterBonus - 100;
        uint256 removeBonus = _amount * 2;

        if (nftOwned >= removeBonus) {
            Inventory.createItemFromTemplate(
                darkMatterId,
                0,
                0,
                0,
                0,
                0,
                _amount,
                msg.sender
            );
        }
        user.darkMatterBonus = 100 + nftOwned - removeBonus;

        emit DarkMatterBonusRemoved(
            msg.sender,
            removeBonus,
            user.darkMatterBonus
        );
    }

    /**
     * @dev External function to train the astronaut. This function can be called only when astronaut has got O2 tanks.
     * @param _amount Vidya amount
     * @param _skill Skill attribution
     * @param _tokenAmount Tank amount
     */
    function trainAstronaut(
        uint256 _amount,
        uint256 _skill,
        uint256 _tokenAmount
    ) external notDeadYet nonReentrant {
        require(_skill <= 2, "Astronaut: Skill outside of range");

        uint256 experienceGained;

        if (_skill == 0) {
            Vidya.safeTransferFrom(msg.sender, vaultAddr, _amount);
            experienceGained = (_amount * expToBuy) / costOfTank;
        } else if (_skill == 1) {
            require(
                DarkMatter.balanceOf(msg.sender) >= _amount,
                "Astronaut: Not enough Dark Matter."
            );
            DarkMatter.burn(msg.sender, _amount);
            experienceGained = (_amount * expToBuy) / maxDarkMatterTank;
        } else {
            require(_tokenAmount <= 15, "Astronaut: Too many tanks");

            Inventory.burn(msg.sender, tankId, _amount);

            experienceGained = _tokenAmount * expToBuy;
        }

        players[msg.sender].experience[_skill] += experienceGained;
        collectDarkMatter(_skill);

        emit AstronautTrained(msg.sender, _skill, experienceGained);
    }

    /**
     * @dev Internal function to return how much dark matter is mined per block by the user.
     * @param _speed Speed attribution
     * @param _harvest Harvest attribution
     * @param _oxygenEquipmet Oxygen Equipment attribution
     * @return How much dark matter is mined
     */
    function DMCollectionRate(
        uint256 _speed,
        uint256 _harvest,
        uint256 _oxygenEquipmet
    ) internal view returns (uint256) {
        return ((maxDarkMatterTank *
            (1000000 - (_speed * _harvest * _oxygenEquipmet))) /
            (1000000 * tankDuration));
    }

    /**
     * @dev Private function to increase level.
     * @param _level Increased level
     */
    function nextLevel(uint256 _level) private {
        if (_level >= levels.length) {
            levels.push(levels[_level] + ((_level + 1) * darkMatterDeci));
            emit LevelUpdated(true, _level);
        }

        emit LevelUpdated(false, _level);
    }

    /**
     * @dev External function to change the name. This function can be called only when astronaut has got O2 tanks.
     * @param _name New name
     */
    function changeName(string memory _name) external notDeadYet nonReentrant {
        Vidya.safeTransferFrom(msg.sender, vaultAddr, fee);
        Vidya.safeTransferFrom(msg.sender, devAddr, fee);

        players[msg.sender].name = _name;

        emit NameChanged(_name);
    }

    /**
     * @dev External function to change the tank duration. This function can be called by only owner.
     * @param _hours Duration hours
     */
    function changeTankDuration(uint256 _hours) external onlyOwner {
        tankDuration = _hours * 1 hours;

        emit TankDurationChanged(tankDuration);
    }

    /**
     * @dev External function to change the max dark matter tank. This function can be called by only owner.
     * @param _newMaxDMTank New max dark matter tank
     */
    function changeTankRate(uint256 _newMaxDMTank) external onlyOwner {
        maxDarkMatterTank = _newMaxDMTank;

        emit TankRateChanged(_newMaxDMTank);
    }

    /**
     * @dev External function to change the cost of tank. This function can be called by only owner.
     * @param _cost Cost of tank
     */
    function changeCostOfTank(uint256 _cost) external onlyOwner {
        costOfTank = _cost;

        emit TankCostChanged(_cost);
    }
}
