// Space-Station
// Is the miner for Dark Matter and uses the Astronaut NFTs as the right to mine
// The SpaceStation Contract only needs to be able to change the stats of an NFT not mint burn or create

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IDarkMatter.sol";

contract SpaceStation is Ownable, ReentrancyGuard {
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

    uint256 dmPerBlockish;
    uint256 numberAstorsnauts;
    uint256 adjustedDMRate;
    uint256 astronautID;
    uint256 O2tanksID;
    uint256 DMID;
    uint256[100] LVLS;
    address vault;
    mapping(uint256 => collectionData) astronauts;

    mapping(string => bool) astronautsNames;

    IDarkMatter DarkMatter;
    IERC20 Vidya;

    struct Item {
        uint256 templateId;
        uint8 feature1;
        uint8 feature2;
        uint8 feature3;
        uint8 feature4;
        uint8 equipmentPosition;
        bool burned;
    }

    struct collectionData {
        string name;
        uint256 rate;
        uint256 collectionStart;
        bool registered;
        uint256 experience;
        uint256[4] features;
        uint256[3] experience;
        uint256[3] levels;
    }

    constructor(
        uint256 _DmPerBlock,
        address _vault,
        address _inventory,
        IDarkMatter _dm,
        IERC20 _vidya,
        uint256 _astronautID,
        uint256 _O2tanksID,
        uint256 _DMID
    ) {
        O2tanksID = _O2tanksID;
        dmPerBlockish = _DmPerBlock;
        inventory = _inventory;
        DarkMatter = _dm;
        Vidya = _vidya;
        astronautID = _astronautID;
        DMID = _DMID;
        vault = _vault;
        LVLS[0] = 100 * 10**18;
        LVLS[1] = 300 * 10**18;
        LVLS[2] = 600 * 10**18;
        LVLS[3] = 1000 * 10**18;
    }

    function register(uint256 _tokenID, string _name) nonReentrant {
        require(!astronautName[_name], "Space Station: Name already taken.");
        Item memory astronaut = inventory.allItems[_tokenID];
        require(
            !astronaut.burned && (astronaut.templateID == astronautID),
            "Space Station: Astronaut Does Not Exisit."
        );
        require(
            inventory.balanceOf(msg.sender, _tokenID) > 0,
            "Space Station: Mission Controls not granted"
        );
        collectionData storage data = astronauts[_tokenID];
        require(!data.registered, "Space Station: Astronaut already in orbit");
        data.name = _name;
        data.feature[0] = uint256(astronaut.feature1);
        data.feature[1] = uint256(astronaut.feature2);
        data.feature[2] = uint256(astronaut.feature3);
        data.feature[3] = uint256(astronaut.feature4);

        data.rate =
            (data.feature[0] + data.feature[1] + 1) *
            (50 + data.feature[3]);

        data collectionStart = block.timestamp;
        data.registered = true;

        emit Launched(msg.sender, _tokenID, _name);
    }

    function collectDarkMatter(uint256 _astronautID, uint256 numberOfTanks) {
        require(
            inventory.balanceOf(msg.sender, _astronautID) > 0,
            "Space Station: Permission not granted"
        );
        require(
            inventory.balanceOf(msg.sender, O2tanksID) >= numberOfTanks &&
                numberOfTanks > 0,
            "Space Station: Miscalculation on O2 tanks"
        );
        collectionData storage data = astronauts[_astronautID];
        require(
            data.collectionStart <= block.timestamp,
            "Space Station: Astronaut not ready for Mission"
        );

        uint256 timeDifference = block.timestamp - data.collectionStart;
        dmToMint = (data.rate * adjustedDMRate * timeDifference) / 500;

        inventory.burn(msg.sender, numberOfTanks);
        data.collectionStart =
            block.timestamp +
            ((256 - data.feature[2]) * timeDiffernce) /
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
    ) nonReentrant {
        collectionData storage data = astroanuts[_tokenID];
        require(data.registered, "Space Station: Astronaut not registered.");
        Item memory stats = inventory.allItems[_tokenID];

        uint256[4] memory xpGained;
        bool adjustNFT;

        if (_vidya > 0 && data.feature[0] < 256) {
            require(
                Vidya.balanceOf(msg.sender) >= _vidya,
                "Space Station: Misscalculation on Vidya amount."
            );
            Vidya.safeTrasferFrom(msg.sender, vault, _amount);
            xpGained[0] = _vidya;
        }

        if (_dm > 0 && data.feature[1] < 256) {
            require(
                DarkMatter.balanceOf(msg.sender) >= _dm,
                "Space Station: Misscalculation on Dark Matter token."
            );
            DarkMatter.burn(msg.sender, _dm);
            xpGained[1] = _dm / 2;
        }

        if (_O2tanks > 0 && data.feature[2] < 256) {
            require(
                inventory.balanceOf(msg.sender, O2tanksID) >= _O2tanks,
                "Space Station: Misscalculation on O2 tanks."
            );
            inventory.burn(msg.sender, O2tanksID, _O2tanks);
            xpGained[2] = (_O2tanks * (10**20));
        }

        if (_numDMNFT > 0 && data.feature[3] < 256) {
            require(
                inventory.balanceOf(msg.sender, DMID) >= _numDMNFT,
                "Space Station: Misscalculation on Dark Matter NFTs."
            );
            inventory.burn(msg.sender, DMID, _numDNFT);
            adjustNFT = true;
            xpGained[3] = _numDNFT;
        }

        xpGained[0] += data.experience[0];
        xpGained[1] += data.experience[1];
        xpGained[2] += data.experience[2];

        for (uint256 index = 0; index < 3; index++) {
            while (
                xpGained[index] > LVLS[data.levels[index]] &&
                data.levels[index] < 100
            ) {
                xpGained[index] = xpGained[index] - LVLS[data.levels[index]];
                data.levels[index] += 1;
                adjustNFT = true;
            }
            data.feature[index] = (data.levels[index] * 255) / 100;
            data.experience[index] = xpGained[index];
        }
        data.feature[3] += xpGained[3];
        if (adjustNFT) {
            inventory.changeFeaturesForItem(
                _tokenID,
                uint8(data.feature[0]),
                uint8(data.feature[1]),
                uint8(data.feature[2]),
                uint8(data.feature[3]),
                stats.equipmentPosition,
                msg.sender
            );
            data.rate =
                (data.feature[0] + data.feature[1] + 1) *
                (50 + data.feature[3]);
        }

        emit Training(msg.sender, data.feature, _tokenID);
    }

    function trainAstronautXP(uint256[3] memory xpGained, uint256 _tokenID)
        nonReentrant
    {
        colectionData storage data = astronauts[_tokenID];
        require(data.registered, "Space Station: Astronaut not registered.");
        Item memory stats = inventory.allItems[_tokenID];

        bool adjustNFT;

        xpGained[0] += data.experience[0];
        xpGained[1] += data.experience[1];
        xpGained[2] += data.experience[2];

        for (uint256 index = 0; index < 3; index++) {
            while (
                xpGained[index] > LVLS[data.levels[index]] &&
                data.levels[index] < 100
            ) {
                xpGained[index] = xpGained[index] - LVLS[data.levels[index]];
                data.levels[index] += 1;
                adjustNFT = true;
            }
            data.feature[index] = (data.levels[index] * 255) / 100;
            data.experience[index] = xpGained[index];
        }

        if (adjustNFT) {
            inventory.changeFeaturesForItem(
                _tokenID,
                uint8(data.feature[0]),
                uint8(data.feature[1]),
                uint8(data.feature[2]),
                uint8(data.feature[3]),
                stats.equipmentPosition,
                msg.sender
            );
            data.rate =
                (data.feature[0] + data.feature[1] + 1) *
                (50 + data.feature[3]);
        }

        emit Training(msg.sender, data.feature, _tokenID);
    }

    function resupply(uint256 _tokenID, uint256 _O2tanks) nonReentrant {
        collectionData storage data = astronauts[_tokenID];

        require(data.registered, "Space Station: Astronaut not registered");
        require(
            data.collectionStart > block.timestamp,
            "Space Station: Astronaut in Orbit"
        );
        require(
            inventory.balanceOf(msg.sender, O2tanksID) >= _O2tanks,
            "Space Station: Misscalculation on supplies"
        );

        uint256 timeDifference = (data.collectionStart - block.timestamp) /
            (2 * _O2Tanks);
        inventory.burn(msg.sender, O2tanksID, _O2tanks);
        data.collectionStart = timeDifference + block.timestamp;

        emit Resupply(msg.sender, _tokenID, data.collectionStart);
    }

    //Needs to pass in the actual value like 10**18 for 1.
    function changeBaseRate(uint256 _DMperBlock) onlyOwner {
        dmPerBlockish = _DMperBlock;
        adjustedDMRate = dmPerBlockish / numberAstorsnauts;

        emit RateChange(adjustedDMRate);
    }

    function createLevels() onlyOwner {
        require(LVLS[99] == 0, "Space Station: Levels already Calculated.");

        uint256 index = 4;
        uint256 deci = 10**20;
        while (LVLS[99] == 0) {
            LVLS[index] = LVLS[index - 1] + ((index + 1) * deci);
            index += 1;
        }

        emit LevelsCreated(LVLS);
    }
}
