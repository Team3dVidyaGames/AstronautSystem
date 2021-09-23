// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DarkMatter Interface
 */
interface IDarkMatter is IERC20 {
    /**
     * @dev External function to mint the token.
     * @param _user Address of user
     * @param _amount Token amount
     */
    function mint(address _user, uint256 _amount) external;

    /**
     * @dev External function to burn the token.
     * @param _user Address of user
     * @param _amount Token amount
     */
    function burn(address _user, uint256 _amount) external;
}
