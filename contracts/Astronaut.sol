// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IInventory.sol";
import "./interfaces/IDarkMatter.sol";

/**
 * @title Astronaut Contract
 */
contract Astronaut is Ownable, ReentrancyGuard {
    using Address for address;
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

    event nameChange(string astroName);
    event durationChanged(uint256 duration);
    event astronautInSpace(address player, string spaceman);

    event maxLevelAcheived(uint256 skill, uint256 levelReached);
    event harvestExtend(address player, uint256 lengthTillEnd);
    event experienceTrained(address player, uint256 skill, uint256 experience);
    event costChange(uint256 tankPrice);

    IERC20 Vidya;
    IDarkMatter DarkMatter;
    IInventory Inventory;

    address public vaultAddr;
    address public devAddr;

    uint256 public constant fee = 5 * 10**18;
    uint256 public constant darkMatterDeci = 10**18;
    uint256 public constant expToBuy = 5 * 10**17;

    uint256 public constant darkMatterId = 18;
    uint256 public constant tankID = 36;
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
     * @param _skill Skill amount
     * @param _tokenId Tank token Id
     * @param _amount Tank amount
     */
    function createAstronaut(
        string memory _name,
        uint256 _skill,
        uint256 _tokenId,
        uint256 _amount
    ) external {
        require(
            !players[msg.sender].created,
            "Astronaut: There can only be one"
        );

        require(_amount <= 15, "Astronaut: Too many tanks");

        Inventory.burn(msg.sender, _tokenId, _amount);

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

        emit AstronautCreated(msg.sender, _name, _skill, _tokenId, _amount);
    }

    /**
     * @dev External function to add tanks.
     * @param _tokenId Tank token Id
     * @param _amount Tank amount
     * @param _skill Skill amount
     */
    function addTanks(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _skill
    ) external notDeadYet {
        require(_amount <= 15, "Astronaut: Too many tanks");

        Inventory.burn(msg.sender, _tokenId, _amount);

        collectDarkMatter(_skill);

        uint256 time = tankDuration * _amount;

        players[msg.sender].timeTillDeath += time;

        emit TanksAdded(
            msg.sender,
            players[msg.sender].timeTillDeath,
            _tokenId,
            _amount,
            _skill
        );
    }

    function harvestDarkMatter(uint256 _skill) public notDeadYet nonReentrant {
        collectDarkMatter(_skill);
    }

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
    }

    function rescueAstronaut(uint256 _tokenId, uint256 _amount)
        public
        aloneInSpace
        nonReentrant
    {
        require(
            !players[msg.sender].created,
            "Astronaut: There can only be one."
        );

        require(_amount <= 15, "Astronaut: Too many tanks");
        Vidya.safeTransferFrom(msg.sender, vaultAddr, fee);

        Inventory.burn(msg.sender, _tokenId, _amount);

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
    }

    function darkMatterNFTBonus(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _skill
    ) public nonReentrant {
        require(_amount <= 15, "Astronaut: Too much Dark Matter at once.");

        Inventory.burn(msg.sender, _tokenId, _amount);

        players[msg.sender].darkMatterBonus += (2 * _amount);

        collectDarkMatter(_skill);
    }

    function removeDarkMatterBonus(uint256 _amount) public nonReentrant {
        Astronauts storage user = players[msg.sender];
        uint256 nftOwned = user.darkMatterBonus - 100;
        uint256 removeBonus = _amount * 2;
        if (nftOwned >= removeBonus) {
            while (_amount > 0) {
                Inventory.createItemFromTemplate(
                    darkMatterId,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    msg.sender
                );
                _amount -= 1;
            }
        }
        user.darkMatterBonus = 100 + nftOwned - removeBonus;
    }

    /**
     * @dev trains the astronaut
     * @param _amount is only used when training skill 0, 1
     * @param _skill is only used when training skill 0, 1
     * @param _tokenId is only used to train skill 2
     * @param _tokenAmount is only used to train skill 2
     */
    function trainAstronaut(
        uint256 _amount,
        uint256 _skill,
        uint256 _tokenId,
        uint256 _tokenAmount
    ) public notDeadYet nonReentrant {
        require(_skill <= 2, "Astronaut: Skill outside of range");
        uint256 experienceGained;
        if (_skill == 0) {
            Vidya.safeTransferFrom(msg.sender, vaultAddr, _amount);
            experienceGained = (_amount * expToBuy) / costOfTank;
        }
        if (_skill == 1) {
            require(
                DarkMatter.balanceOf(msg.sender) >= _amount,
                "Astronaut: Not enough Dark Matter."
            );
            DarkMatter.burn(msg.sender, _amount);
            experienceGained = (_amount * expToBuy) / maxDarkMatterTank;
        }
        if (_skill == 2) {
            require(_tokenAmount <= 15, "Astronaut: Too many tanks");

            Inventory.burn(msg.sender, _tokenId, _amount);

            experienceGained = _tokenAmount * expToBuy;
        }
        players[msg.sender].experience[_skill] += experienceGained;
        collectDarkMatter(_skill);

        emit experienceTrained(msg.sender, _skill, experienceGained);
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
     * @dev continues to increase the levels, if the level has not already been made.
     */

    function nextLevel(uint256 _level) private {
        if (_level >= levels.length) {
            levels.push(levels[_level] + ((_level + 1) * darkMatterDeci));
        }
    }

    function changeName(string memory _name) public notDeadYet nonReentrant {
        Vidya.safeTransferFrom(msg.sender, vaultAddr, fee);
        Vidya.safeTransferFrom(msg.sender, devAddr, fee);

        players[msg.sender].name = _name;
        emit nameChange(_name);
    }

    function changeTankDuration(uint256 _hours) public onlyOwner {
        tankDuration = _hours * 1 hours;
        emit durationChanged(tankDuration);
    }

    function changeTankRate(uint256 _DMamount) public onlyOwner {
        // maxDarkMatterTank = _DMamount * scale;
        // emit tankRateChange(_DMamount);
    }

    function changeCostOfTank(uint256 _amount) public onlyOwner {
        costOfTank = _amount;
        emit costChange(_amount);
    }
}
