// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/**
 * @title Inventory Interface
 */
interface IInventory {
    function getIndividualCount(uint256 _templateId) external returns (uint256);

    function getTemplateIDsByTokenIDs(uint256[] memory _tokenIds)
        external
        returns (uint256[] memory);

    function createFromTemplate(
        uint256 _templateId,
        uint8 _feature1,
        uint8 _feature2,
        uint8 _feature3,
        uint8 _feature4,
        uint8 _equipmentPosition
    ) external returns (uint256);

    function burn(uint256 _tokenId) external returns (bool);

    function ownerOf(uint256 tokenId) external returns (address);
}
