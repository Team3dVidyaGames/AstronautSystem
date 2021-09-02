// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IInventory.sol";

/**
 * @title Astronaut Contract
 */
contract Astronaut is Ownable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 vidya;
    IERC20 dm;

    IInventory public inventory =
        IInventory(0x9680223F7069203E361f55fEFC89B7c1A952CDcc); // Mainnet address: 0x9680223f7069203e361f55fefc89b7c1a952cdcc

    uint256 constant fee = 5 * 10**18;
    uint256 constant darkMatterDeci = 10**18;
    uint256 constant expToBuy = 5 * 10**17;
    address dev;
    address vault;

    uint256 DMID = 18;
    uint256 tankID = 36;

    event tankRateChange(uint256 tankRate);
    event nameChange(string astroName);
    event durationChanged(uint256 duration);
    event astronautInSpace(address player, string spaceman);
    event creation();
    event maxLevelAcheived(uint256 skill, uint256 levelReached);
    event harvestExtend(address player, uint256 lengthTillEnd);
    event experienceTrained(address player, uint256 skill, uint256 experience);
    event costChange(uint256 tankPrice);

    modifier NotDeadYet() {
        require(
            players[msg.sender].timeTillDeath >= block.timestamp,
            "Astronaut: Astronaut lost in Space."
        );
        _;
    }

    modifier AloneInSpace() {
        require(
            players[msg.sender].timeTillDeath < block.timestamp,
            "Astronaut: Still in contact with SpaceMan"
        );
        _;
    }

    struct Astronauts {
        string name;
        uint256[3] multiplier; //speed, harvest, oxygen_equipmet
        uint256[3] level;
        uint256[3] experience;
        uint256 timeTillDeath;
        uint256 darkMatterCollectionRate;
        uint256 lastCollected;
        bool created;
        uint256 DMBonus;
    }

    uint256 maxDMTank;
    uint256[] levels;
    uint256 tankDuration;
    uint256 constant maxLevel = 99;
    uint256 costOfTank;
    mapping(address => Astronauts) players;

    constructor(
        address _dev,
        address _vault,
        IERC20 _vidya,
        IERC20 _DM
    ) {
        dev = _dev;
        vidya = _vidya;
        dm = _DM;
        vault = _vault;
        levels.push(1 * darkMatterDeci); //0-1
        levels.push(3 * darkMatterDeci); //1-2
        levels.push(6 * darkMatterDeci); //2-3
        levels.push(10 * darkMatterDeci); //3-4
        levels.push(15 * darkMatterDeci); //4-5
        levels.push(21 * darkMatterDeci); //5-6
        emit creation();
    }

    function createAstronaut(
        string memory _name,
        uint256 _skill,
        uint256[] memory _tokenID
    ) public {
        require(
            !players[msg.sender].created,
            "Astronaut: There can only be one."
        );

        uint256 _numTanks = _tokenID.length;
        require(_numTanks <= 15, "Astronaut: To many tanks");

        uint256 i = 0;

        while (i < _tokenID.length) {
            if (!burnNFT(tankID, _tokenID[i])) {
                _numTanks -= 1;
            }
            i += 1;
        }

        Astronauts memory holder;
        holder.name = _name;
        holder.multiplier[_skill] = 95;
        holder.multiplier[(_skill + 1) % 3] = 100;
        holder.multiplier[(_skill + 2) % 3] = 100;
        holder.level[_skill] = 5;
        holder.timeTillDeath = block.timestamp + (tankDuration * _numTanks);
        holder.lastCollected = block.timestamp;
        holder.darkMatterCollectionRate = DMcollectionRate(100, 100, 95);
        holder.DMBonus = 100;
        holder.created = true;

        players[msg.sender] = holder;

        emit astronautInSpace(msg.sender, _name);
    }

    function addTanks(uint256[] memory _tokenID, uint256 _skill)
        public
        NotDeadYet
        nonReentrant
    {
        uint256 _numTanks = _tokenID.length;
        require(_numTanks <= 15, "Astronaut: To many tanks");
        uint256 i = 0;
        while (i < _tokenID.length) {
            if (!burnNFT(tankID, _tokenID[i])) {
                _numTanks -= 1;
            }
            i += 1;
        }
        collectDarkMatter(_skill);
        uint256 time = tankDuration * _numTanks;
        players[msg.sender].timeTillDeath += time;

        emit harvestExtend(msg.sender, players[msg.sender].timeTillDeath);
    }

    function harvestDarkMatter(uint256 _skill) public NotDeadYet nonReentrant {
        collectDarkMatter(_skill);
    }

    function collectDarkMatter(uint256 _skill) internal {
        Astronauts storage user = players[msg.sender];

        uint256 darkMatter = (user.DMBonus *
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
        user.darkMatterCollectionRate = DMcollectionRate(
            user.multiplier[0],
            user.multiplier[1],
            user.multiplier[2]
        );
        dm.mint(msg.sender, darkMatter); //mint dark matter
    }

    function rescueAstronaut(uint256[] memory _tokenID)
        public
        AloneInSpace
        nonReentrant
    {
        require(
            !players[msg.sender].created,
            "Astronaut: There can only be one."
        );

        uint256 _numTanks = _tokenID.length;
        require(_numTanks <= 15, "Astronaut: To many tanks");
        vidya.safeTransferFrom(msg.sender, vault, fee);
        uint256 i = 0;
        while (i < _tokenID.length) {
            if (!burnNFT(tankID, _tokenID[i])) {
                _numTanks -= 1;
            }
            i += 1;
        }

        Astronauts storage user = players[msg.sender];

        for (i = 0; i < 3; i++) {
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
        user.darkMatterCollectionRate = DMcollectionRate(
            user.multiplier[0],
            user.multiplier[1],
            user.multiplier[2]
        );
        user.timeTillDeath = block.timestamp + (_numTanks * tankDuration);
    }

    function darkMatterNFTBonus(uint256[] memory _tokenID, uint256 _skill)
        public
        nonReentrant
    {
        uint256 _amountDM = _tokenID.length;
        require(_amountDM <= 15, "Astronaut: To much Dark Matter at once.");

        uint256 i = 0;

        while (i < _tokenID.length) {
            if (!burnNFT(DMID, _tokenID[i])) {
                _amountDM -= 1;
            }
            i += 1;
        }
        players[msg.sender].DMBonus += (2 * _amountDM);
        collectDarkMatter(_skill);
    }

    function removeDarkMatterBonus(uint256 _amount) public nonReentrant {
        Astronauts storage user = players[msg.sender];
        uint256 nftOwned = user.DMBonus - 100;
        uint256 removeBonus = _amount * 2;
        if (nftOwned >= removeBonus) {
            while (_amount > 0) {
                inventory.createFromTemplate(DMID, 0, 0, 0, 0, 0);
                _amount -= 1;
            }
        }
        user.DMBonus = 100 + nftOwned - removeBonus;
    }

    /**
     * @dev trains the astronaut
     * @param _amount is only used when training skill 0, 1
     * @param _tokenID is only used to train skill 2
     */

    function trainAstronaut(
        uint256 _amount,
        uint256 _skill,
        uint256[] memory _tokenID
    ) public NotDeadYet nonReentrant {
        require(_skill <= 2, "Astronaut: Skill outside of range");
        uint256 experienceGained;
        if (_skill == 0) {
            vidya.safeTransferFrom(msg.sender, vault, _amount);
            experienceGained = (_amount * expToBuy) / costOfTank;
        }
        if (_skill == 1) {
            require(
                dm.balanceOf(msg.sender) >= _amount,
                "Astronaut: Not enough Dark Matter."
            );
            dm.burn(msg.sender, _amount);
            experienceGained = (_amount * expToBuy) / maxDMTank;
        }
        if (_skill == 2) {
            uint256 _numTanks = _tokenID.length;
            require(_numTanks <= 15, "Astronaut: To many tanks");

            uint256 i = 0;
            while (i < _tokenID.length) {
                if (!burnNFT(tankID, _tokenID[i])) {
                    _numTanks -= 1;
                }
                i += 1;
            }
            experienceGained = _numTanks * expToBuy;
        }
        players[msg.sender].experience[_skill] += experienceGained;
        collectDarkMatter(_skill);

        emit experienceTrained(msg.sender, _skill, experienceGained);
    }

    /**
     * @dev returns how much dm is mined per block by the user.
     */

    function DMcollectionRate(
        uint256 speed,
        uint256 harvest,
        uint256 oxygen_equipmet
    ) internal view returns (uint256) {
        //100**3 is used to simulate multipling % together
        return ((maxDMTank * (1000000 - (speed * harvest * oxygen_equipmet))) /
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

    function burnNFT(uint256 _template, uint256 _tokenID)
        internal
        view
        returns (bool)
    {
        if (inventory.ownerOf(_tokenID) == msg.sender) {
            uint256[] memory tempID = inventory.getTemplateIDsByTokenIDs(
                [_tokenID]
            );
            if (_template == tempID[0]) {
                return inventory.burn(_tokenID);
            }
        }
        return false;
    }

    function changeName(string memory _name) public NotDeadYet nonReentrant {
        vidya.safeTransferFrom(msg.sender, vault, fee);
        vidya.safeTransferFrom(msg.sender, dev, fee);

        players[msg.sender].name = _name;
        emit nameChange(_name);
    }

    function changeTankDuration(uint256 _hours) public onlyOwner {
        tankDuration = _hours * 1 hours;
        emit durationChanged(tankDuration);
    }

    function changeTankRate(uint256 _DMamount) public onlyOwner {
        maxDMTank = _DMamount;
        emit tankRateChange(_DMamount);
    }

    function changeCostOfTank(uint256 _amount) public onlyOwner {
        costOfTank = _amount;
        emit costChange(_amount);
    }
}
