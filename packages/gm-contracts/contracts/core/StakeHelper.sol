
// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IAggregationExecutor {
    function callBytes(bytes calldata data, address srcSpender) external payable; // 0xd9c45357
}

interface IVault {
    function stake(address _account, address _token, uint256 _amount) external;
    function deposit(address _account, address _token, uint256 _amount) external;
}

interface IAggregatorRouter {

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }


    function swap(
        IAggregationExecutor caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount);
}

contract StakeHelper {
    using SafeERC20 for IERC20;
    IVault public vault;
    IAggregatorRouter public aggregatorRouter;
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    constructor(IVault _vault, IAggregatorRouter _aggregatorRouter) {
        vault = _vault;
        aggregatorRouter = _aggregatorRouter;
    }
    function isETH(IERC20 token) internal pure returns (bool) {
        return (address(token) == ETH_ADDRESS);
    }

    function swapAndStake(
        IAggregationExecutor caller,
        IAggregatorRouter.SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount) {
        require(desc.dstReceiver == address(this), "Invalid SwapDescription.dstReceiver");
        if (!isETH(desc.srcToken)) {
            IERC20(desc.srcToken).safeTransferFrom(msg.sender, address(this), desc.amount);
            IERC20(desc.srcToken).safeApprove(address(aggregatorRouter), desc.amount);
        }
        returnAmount = aggregatorRouter.swap{value: msg.value}(caller, desc, data);
        require(returnAmount > 0, "Invalid returnAmount");
        IERC20(desc.dstToken).safeApprove(address(vault), returnAmount);
        vault.stake(msg.sender, address(desc.dstToken), returnAmount);
    }
    function swapAndDeposit(
        IAggregationExecutor caller,
        IAggregatorRouter.SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount) {
        require(desc.dstReceiver == address(this), "Invalid SwapDescription.dstReceiver");
        if (!isETH(desc.srcToken)) {
            IERC20(desc.srcToken).safeTransferFrom(msg.sender, address(this), desc.amount);
            IERC20(desc.srcToken).safeApprove(address(aggregatorRouter), desc.amount);
        }
        returnAmount = aggregatorRouter.swap{value: msg.value}(caller, desc, data);
        require(returnAmount > 0, "Invalid returnAmount");
        IERC20(desc.dstToken).safeApprove(address(vault), returnAmount);
        vault.deposit(msg.sender, address(desc.dstToken), returnAmount);
    }
}

