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

    /// @notice Event emitted when user is registered the astronaut.
    event Registered(address user, uint256 tokenId, string name);

    /// @notice Event emitted when user collected the dark matter.
    event DarkMatterCollected(
        address user,
        string astronautName,
        uint256 darkMatterAmount,
        uint256 restTime
    );

    /// @notice Event emitted when user resupplied the astronaut.
    event Resupplied(
        address user,
        uint256 astronautId,
        uint256 collectionStartTime,
        uint256 tankAmount
    );

    /// @notice Event emitted when user trained the astronaut.
    event AstronautTrained(address user, CollectionData data);

    /// @notice Event emitted when the base rate is changed.
    event BaseRateChange(uint256 newRate);

    /// @notice Event emitted when the levels are created.
    event LevelsCreated(uint256[100] levels);

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
    uint256 public O2TankId;
    uint256 public dmId;
    uint256[100] public levels;
    address public vaultAddress;

    /**
     * @dev Constructor function
     * @param _Inventory Interface of Inventory
     * @param _DarkMatter Interface of DarkMatter
     * @param _Vidya Interface of Vidya (0x3D3D35bb9bEC23b06Ca00fe472b50E7A4c692C30)
     * @param _vaultAddress Vault Address
     * @param _dmPerBlock ??
     * @param _astronautId Astronaut token id
     * @param _O2TankId Tank token id
     * @param _dmId DarkMatter token id
     */
    constructor(
        IInventory _Inventory,
        IDarkMatter _DarkMatter,
        IERC20 _Vidya,
        address _vaultAddress,
        uint256 _dmPerBlock,
        uint256 _astronautId,
        uint256 _O2TankId,
        uint256 _dmId
    ) {
        Inventory = _Inventory;
        DarkMatter = _DarkMatter;
        Vidya = _Vidya;
        vaultAddress = _vaultAddress;
        dmPerBlock = _dmPerBlock;
        astronautId = _astronautId;
        O2TankId = _O2TankId;
        dmId = _dmId;

        levels[0] = 100 * 10**18;
        levels[1] = 300 * 10**18;
        levels[2] = 600 * 10**18;
        levels[3] = 1000 * 10**18;

        emit SpaceStationDeployed();
    }

    /**
     * @dev External function to register the astronaut.
     * @param _tokenId Astronaut Item token Id
     * @param _name Astronaut name
     */
    function register(uint256 _tokenId, string memory _name)
        external
        nonReentrant
    {
        require(
            !astronautsNames[_name],
            "Space Station: Name is already taken"
        );
        astronautsNames[_name] = true;

        IInventory.Item memory astronaut = Inventory.allItems(_tokenId);

        require(
            !astronaut.burned && (astronaut.templateId == astronautId),
            "Space Station: Astronaut Does Not Exisit"
        );

        CollectionData storage data = astronauts[_tokenId];

        require(
            !data.registered,
            "Space Station: Astronaut is already registered"
        );

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

        emit Registered(msg.sender, _tokenId, _name);
    }

    /**
     * @dev External function to collect the dark matter.
     * @param _astronautId Astronaut Item token Id
     * @param _tankAmount O2 tank amount
     */
    function collectDarkMatter(uint256 _astronautId, uint256 _tankAmount)
        external
    {
        require(
            Inventory.balanceOf(msg.sender, _astronautId) > 0,
            "Space Station: Permission is not granted"
        );

        require(
            Inventory.balanceOf(msg.sender, O2TankId) >= _tankAmount &&
                _tankAmount > 0,
            "Space Station: Miscalculation on O2 tanks"
        );

        CollectionData storage data = astronauts[_astronautId];

        require(data.registered, "Space Station: Astronaut not registered.");

        require(
            data.collectionStart <= block.timestamp,
            "Space Station: Astronaut is not ready for Mission"
        );

        uint256 timeDifference = block.timestamp - data.collectionStart;

        uint256 dmToMint = (data.rate * adjustedDmRate * timeDifference) / 500;

        Inventory.burn(msg.sender, O2TankId, _tankAmount);

        data.collectionStart =
            block.timestamp +
            ((256 - data.features[2]) * timeDifference) /
            (_tankAmount * 512);

        data.experience += dmToMint;

        DarkMatter.mint(msg.sender, dmToMint);

        emit DarkMatterCollected(
            msg.sender,
            data.name,
            dmToMint,
            data.collectionStart
        );
    }

    /**
     * @dev External function to train the astronaut.
     * @param _astronautId Astronaut Item token Id
     * @param _vidyaAmount Vidya amount user holds
     * @param _dmAmount Dark Matter amount
     * @param _O2tanks O2 tank amount
     * @param _dmNFTAmount Dark Matter NFT amount
     */
    function trainAstronaut(
        uint256 _astronautId,
        uint256 _vidyaAmount,
        uint256 _dmAmount,
        uint256 _O2tanks,
        uint256 _dmNFTAmount
    ) external nonReentrant {
        CollectionData storage data = astronauts[_astronautId];

        require(data.registered, "Space Station: Astronaut is not registered");

        uint256[3] memory xpGained;
        bool adjustNFT;

        if (_vidyaAmount > 0 && data.features[0] < 256) {
            Vidya.safeTransferFrom(msg.sender, vaultAddress, _vidyaAmount);
            xpGained[0] = _vidyaAmount;
        }

        if (_dmAmount > 0 && data.features[1] < 256) {
            require(
                DarkMatter.balanceOf(msg.sender) >= _dmAmount,
                "Space Station: Misscalculation on Dark Matter token."
            );
            DarkMatter.burn(msg.sender, _dmAmount);
            xpGained[1] = _dmAmount / 2;
        }

        if (_O2tanks > 0 && data.features[2] < 256) {
            require(
                Inventory.balanceOf(msg.sender, O2TankId) >= _O2tanks,
                "Space Station: Misscalculation on O2 tanks."
            );
            Inventory.burn(msg.sender, O2TankId, _O2tanks);
            xpGained[2] = (_O2tanks * (10**20));
        }

        if (_dmNFTAmount > 0 && data.features[3] < 256) {
            require(
                Inventory.balanceOf(msg.sender, dmId) >= _dmNFTAmount,
                "Space Station: Misscalculation on Dark Matter NFTs."
            );
            Inventory.burn(msg.sender, dmId, _dmNFTAmount);
            adjustNFT = true;
            data.features[3] += _dmNFTAmount;
        }

        trainAstronautXP(xpGained, _astronautId, adjustNFT);

        emit AstronautTrained(msg.sender, data);
    }

    /**
     * @dev Public function to train the astronaut XP.
     * @param _xpGained Array of XP gained
     * @param _astronautId Astronaut token Id
     * @param _adjustNFT Adjust NFT
     */
    function trainAstronautXP(
        uint256[3] memory _xpGained,
        uint256 _astronautId,
        bool _adjustNFT
    ) public nonReentrant {
        CollectionData storage data = astronauts[_astronautId];

        require(data.registered, "Space Station: Astronaut is not registered");

        IInventory.Item memory stats = Inventory.allItems(_astronautId);

        bool adjustNFT = _adjustNFT;

        _xpGained[0] += data.experiences[0];
        _xpGained[1] += data.experiences[1];
        _xpGained[2] += data.experiences[2];

        for (uint8 i = 0; i < 3; i++) {
            while (
                _xpGained[i] > levels[data.levels[i]] && data.levels[i] < 100
            ) {
                _xpGained[i] = _xpGained[i] - levels[data.levels[i]];
                data.levels[i]++;
                adjustNFT = true;
            }
            data.features[i] = (data.levels[i] * 255) / 100;
            data.experiences[i] = _xpGained[i];
        }

        if (adjustNFT) {
            Inventory.changeFeaturesForItem(
                _astronautId,
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

        emit AstronautTrained(msg.sender, data);
    }

    /**
     * @dev External function to resupply the astronaut.
     * @param _astronautId Astronaut token Id
     * @param _tankAmount O2 tanks amount
     */
    function resupply(uint256 _astronautId, uint256 _tankAmount)
        external
        nonReentrant
    {
        CollectionData storage data = astronauts[_astronautId];

        require(data.registered, "Space Station: Astronaut is not registered");
        require(
            data.collectionStart > block.timestamp,
            "Space Station: Astronaut is not ready for Mission"
        );
        require(
            Inventory.balanceOf(msg.sender, O2TankId) >= _tankAmount,
            "Space Station: Misscalculation on supplies"
        );

        uint256 timeDifference = (data.collectionStart - block.timestamp) /
            (2 * _tankAmount);

        Inventory.burn(msg.sender, O2TankId, _tankAmount);
        data.collectionStart = timeDifference + block.timestamp;

        emit Resupplied(
            msg.sender,
            _astronautId,
            data.collectionStart,
            _tankAmount
        );
    }

    /**
     * @dev External function to change the base rate. This function can be called by only owner.
     * @param _dmPerBlock Dark matter block
     */
    function changeBaseRate(uint256 _dmPerBlock) external onlyOwner {
        dmPerBlock = _dmPerBlock;
        adjustedDmRate = dmPerBlock / numberAstorsnauts;

        emit BaseRateChange(adjustedDmRate);
    }

    /**
     * @dev External function to create the levels. This function can be called by only owner.
     */
    function createLevels() external onlyOwner {
        require(
            levels[99] == 0,
            "Space Station: Levels are already calculated."
        );

        uint256 index = 4;
        uint256 deci = 10**20;

        while (levels[99] == 0) {
            levels[index] = levels[index - 1] + ((index + 1) * deci);
            index++;
        }

        emit LevelsCreated(levels);
    }
}
