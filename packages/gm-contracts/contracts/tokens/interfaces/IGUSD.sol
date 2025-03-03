// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IGUSD {
    function burn(address _account, uint256 _amount) external;

    function mint(address _account, uint256 _amount) external;

    function balanceOf(address _account) external view returns (uint256);
}
