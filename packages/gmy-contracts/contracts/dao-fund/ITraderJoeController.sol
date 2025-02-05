// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface ITraderJoeController {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory pairBinSteps,
        address[] memory tokenPath,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}