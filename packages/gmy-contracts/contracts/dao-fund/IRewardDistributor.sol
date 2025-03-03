// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IRewardDistributor {
    function rewardToken() external view returns (address);
    function rewardTracker() external view returns (address);
    function setTokensPerInterval(uint256 _amount) external;
    function tokensPerInterval() external view returns (uint256);
    function pendingRewards() external view returns (uint256);
    function distribute() external returns (uint256);
}
