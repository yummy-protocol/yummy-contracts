// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IGmManager {
    function unstake(address _account, address _tokenOut, uint256 _gmAmount) external returns (uint256);

    function stake(address _account, address _token, uint256 _amount) external returns (uint256);
}
