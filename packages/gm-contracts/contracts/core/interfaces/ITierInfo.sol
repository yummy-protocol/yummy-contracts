// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ITierInfo {
    function getTierInfo(address _account) external view returns (uint256);
}
