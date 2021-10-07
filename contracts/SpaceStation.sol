// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDarkMatter.sol";
import "./interfaces/IInventory.sol";

/**
 * @title SpaceStation Contract
 */
contract SpaceStation is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Event emitted only on construction.
    event SpaceStationDeployed();

    event Launched(address sender, uint256 ID, string name);
    event RateChange(uint256 rate);
    event DarkMatterCollected(
        address sender,
        string name,
        uint256 amount,
        uint256 RestTime
    );
    event LevelsCreated(uint256[100] levels);
    event Training(address trainer, uint256[4] features, uint256 tokenID);

    struct CollectionData {
        string name;
        bool registered;
        uint256 rate;
        uint256 collectionStart;
        uint256 experience;
        uint256[3] experiences;
        uint256[3] levels;
        uint256[4] features;
    }

    mapping(uint256 => CollectionData) public astronauts;
    mapping(string => bool) public astronautsNames;

    IInventory public Inventory;
    IDarkMatter public DarkMatter;
    IERC20 public Vidya;

    uint256 public dmPerBlock;
    uint256 public numberAstorsnauts;
    uint256 public adjustedDmRate;
    uint256 public astronautId;
    uint256 public O2tanksId;
    uint256 public dmId;
    address public vault;
    uint256[100] public levels;

    constructor(
        IInventory _Inventory,
        IDarkMatter _DarkMatter,
        IERC20 _Vidya,
        address _vault,
        uint256 _dmPerBlock,
        uint256 _astronautId,
        uint256 _O2tanksId,
        uint256 _dmId
    ) {
        Inventory = _Inventory;
        DarkMatter = _DarkMatter;
        Vidya = _Vidya;
        vault = _vault;
        dmPerBlock = _dmPerBlock;
        astronautId = _astronautId;
        O2tanksId = _O2tanksId;
        dmId = _dmId;

        levels[0] = 100 * 10**18;
        levels[1] = 300 * 10**18;
        levels[2] = 600 * 10**18;
        levels[3] = 1000 * 10**18;

        emit SpaceStationDeployed();
    }

    function register(uint256 _tokenID, string memory _name)
        external
        nonReentrant
    {
        require(!astronautsNames[_name], "Space Station: Name already taken.");
        astronautsNames[_name] = true;

        IInventory.Item memory astronaut = Inventory.allItems(_tokenID);

        require(
            !astronaut.burned && (astronaut.templateId == astronautId),
            "Space Station: Astronaut Does Not Exisit."
        );
        require(
            Inventory.balanceOf(msg.sender, _tokenID) > 0,
            "Space Station: Mission Controls not granted"
        );

        CollectionData storage data = astronauts[_tokenID];
        require(!data.registered, "Space Station: Astronaut already in orbit");
        data.name = _name;
        data.features[0] = uint256(astronaut.feature1);
        data.features[1] = uint256(astronaut.feature2);
        data.features[2] = uint256(astronaut.feature3);
        data.features[3] = uint256(astronaut.feature4);

        data.rate =
            (data.features[0] + data.features[1] + 1) *
            (50 + data.features[3]);

        data.collectionStart = block.timestamp;
        data.registered = true;

        emit Launched(msg.sender, _tokenID, _name);
    }

    function collectDarkMatter(uint256 _astronautId, uint256 numberOfTanks)
        external
    {
        require(
            Inventory.balanceOf(msg.sender, _astronautId) > 0,
            "Space Station: Permission not granted"
        );
        require(
            Inventory.balanceOf(msg.sender, O2tanksId) >= numberOfTanks &&
                numberOfTanks > 0,
            "Space Station: Miscalculation on O2 tanks"
        );
        CollectionData storage data = astronauts[_astronautId];
        require(
            data.collectionStart <= block.timestamp,
            "Space Station: Astronaut not ready for Mission"
        );

        uint256 timeDifference = block.timestamp - data.collectionStart;
        uint256 dmToMint = (data.rate * adjustedDmRate * timeDifference) / 500;

        Inventory.burn(msg.sender, _astronautId, numberOfTanks);

        data.collectionStart =
            block.timestamp +
            ((256 - data.features[2]) * timeDifference) /
            (numberOfTanks * 512);
        data.experience += dmToMint;
        DarkMatter.mint(msg.sender, dmToMint);

        emit DarkMatterCollected(
            msg.sender,
            data.name,
            dmToMint,
            data.collectionStart
        );
    }

    function trainAstronaut(
        uint256 _tokenID,
        uint256 _numDMNFT,
        uint256 _O2tanks,
        uint256 _vidya,
        uint256 _dm
    ) external nonReentrant {
        CollectionData storage data = astronauts[_tokenID];
        require(data.registered, "Space Station: Astronaut not registered.");
        IInventory.Item memory stats = Inventory.allItems(_tokenID);

        uint256[4] memory xpGained;
        bool adjustNFT;

        if (_vidya > 0 && data.features[0] < 256) {
            require(
                Vidya.balanceOf(msg.sender) >= _vidya,
                "Space Station: Misscalculation on Vidya amount."
            );
            Vidya.safeTransferFrom(msg.sender, vault, _vidya);
            xpGained[0] = _vidya;
        }

        if (_dm > 0 && data.features[1] < 256) {
            require(
                DarkMatter.balanceOf(msg.sender) >= _dm,
                "Space Station: Misscalculation on Dark Matter token."
            );
            DarkMatter.burn(msg.sender, _dm);
            xpGained[1] = _dm / 2;
        }

        if (_O2tanks > 0 && data.features[2] < 256) {
            require(
                Inventory.balanceOf(msg.sender, O2tanksId) >= _O2tanks,
                "Space Station: Misscalculation on O2 tanks."
            );
            Inventory.burn(msg.sender, O2tanksId, _O2tanks);
            xpGained[2] = (_O2tanks * (10**20));
        }

        if (_numDMNFT > 0 && data.features[3] < 256) {
            require(
                Inventory.balanceOf(msg.sender, dmId) >= _numDMNFT,
                "Space Station: Misscalculation on Dark Matter NFTs."
            );
            Inventory.burn(msg.sender, dmId, _numDMNFT);
            adjustNFT = true;
            xpGained[3] = _numDMNFT;
        }

        xpGained[0] += data.experiences[0];
        xpGained[1] += data.experiences[1];
        xpGained[2] += data.experiences[2];

        for (uint256 index = 0; index < 3; index++) {
            while (
                xpGained[index] > levels[data.levels[index]] &&
                data.levels[index] < 100
            ) {
                xpGained[index] = xpGained[index] - levels[data.levels[index]];
                data.levels[index] += 1;
                adjustNFT = true;
            }
            data.features[index] = (data.levels[index] * 255) / 100;
            data.experiences[index] = xpGained[index];
        }
        data.features[3] += xpGained[3];
        if (adjustNFT) {
            Inventory.changeFeaturesForItem(
                _tokenID,
                uint8(data.features[0]),
                uint8(data.features[1]),
                uint8(data.features[2]),
                uint8(data.features[3]),
                stats.equipmentPosition,
                msg.sender
            );
            data.rate =
                (data.features[0] + data.features[1] + 1) *
                (50 + data.features[3]);
        }

        emit Training(msg.sender, data.features, _tokenID);
    }

    function trainAstronautXP(uint256[3] memory xpGained, uint256 _tokenID)
        external
        nonReentrant
    {
        CollectionData storage data = astronauts[_tokenID];
        require(data.registered, "Space Station: Astronaut not registered.");
        IInventory.Item memory stats = Inventory.allItems(_tokenID);

        bool adjustNFT;

        xpGained[0] += data.experiences[0];
        xpGained[1] += data.experiences[1];
        xpGained[2] += data.experiences[2];

        for (uint256 index = 0; index < 3; index++) {
            while (
                xpGained[index] > levels[data.levels[index]] &&
                data.levels[index] < 100
            ) {
                xpGained[index] = xpGained[index] - levels[data.levels[index]];
                data.levels[index] += 1;
                adjustNFT = true;
            }
            data.features[index] = (data.levels[index] * 255) / 100;
            data.experiences[index] = xpGained[index];
        }

        if (adjustNFT) {
            Inventory.changeFeaturesForItem(
                _tokenID,
                uint8(data.features[0]),
                uint8(data.features[1]),
                uint8(data.features[2]),
                uint8(data.features[3]),
                stats.equipmentPosition,
                msg.sender
            );
            data.rate =
                (data.features[0] + data.features[1] + 1) *
                (50 + data.features[3]);
        }

        emit Training(msg.sender, data.features, _tokenID);
    }

    function resupply(uint256 _tokenID, uint256 _O2tanks)
        external
        nonReentrant
    {
        CollectionData storage data = astronauts[_tokenID];

        require(data.registered, "Space Station: Astronaut not registered");
        require(
            data.collectionStart > block.timestamp,
            "Space Station: Astronaut in Orbit"
        );
        require(
            Inventory.balanceOf(msg.sender, O2tanksId) >= _O2tanks,
            "Space Station: Misscalculation on supplies"
        );

        uint256 timeDifference = (data.collectionStart - block.timestamp) /
            (2 * _O2tanks);
        Inventory.burn(msg.sender, O2tanksId, _O2tanks);
        data.collectionStart = timeDifference + block.timestamp;

        //       emit Resupply(msg.sender, _tokenID, data.collectionStart);
    }

    //Needs to pass in the actual value like 10**18 for 1.
    function changeBaseRate(uint256 _dmperBlock) external onlyOwner {
        dmPerBlock = _dmperBlock;
        adjustedDmRate = dmPerBlock / numberAstorsnauts;

        emit RateChange(adjustedDmRate);
    }

    function createLevels() external onlyOwner {
        require(levels[99] == 0, "Space Station: Levels already Calculated.");

        uint256 index = 4;
        uint256 deci = 10**20;
        while (levels[99] == 0) {
            levels[index] = levels[index - 1] + ((index + 1) * deci);
            index += 1;
        }

        emit LevelsCreated(levels);
    }
}
