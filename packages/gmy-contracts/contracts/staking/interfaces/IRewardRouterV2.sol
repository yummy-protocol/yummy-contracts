// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouterV2 {
    function feeGlpTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);

    function feeGmTracker() external view returns (address);
    function stakedGmTracker() external view returns (address);
}
