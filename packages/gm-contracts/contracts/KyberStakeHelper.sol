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

interface IKyberRouter {

    struct SwapDescriptionV2 {
        IERC20 srcToken;
        IERC20 dstToken;
        address[] srcReceivers; // transfer src token to these addresses, default
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    /// @dev  use for swapGeneric and swap to avoid stack too deep
    struct SwapExecutionParams {
        address callTarget; // call this address
        address approveTarget; // approve this address if _APPROVE_FUND set
        bytes targetData;
        SwapDescriptionV2 desc;
        bytes clientData;
    }


    function swap(SwapExecutionParams calldata execution)
    external
    payable
    returns (uint256 returnAmount, uint256 gasUsed);

    function swapSimpleMode(
        IAggregationExecutor caller,
        SwapDescriptionV2 memory desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 gasUsed);
}

contract KyberStakeHelper {
    using SafeERC20 for IERC20;
    IVault public vault;
    IKyberRouter public kyberRouter;
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    constructor(IVault _vault, IKyberRouter _kyberRouter) {
        vault = _vault;
        kyberRouter = _kyberRouter;
    }
    function isETH(IERC20 token) internal pure returns (bool) {
        return (address(token) == ETH_ADDRESS);
    }

    function _swap(
        IKyberRouter.SwapExecutionParams calldata execution
    ) internal returns (uint256 returnAmount, uint256 gasLeft) {
        IKyberRouter.SwapDescriptionV2 memory desc = execution.desc;
        require(desc.dstReceiver == address(this), "Invalid SwapDescription.dstReceiver");
        if (!isETH(desc.srcToken)) {
            IERC20(desc.srcToken).safeTransferFrom(msg.sender, address(this), desc.amount);
            IERC20(desc.srcToken).safeApprove(address(kyberRouter), desc.amount);
        }
        (returnAmount, gasLeft) = kyberRouter.swap{value: msg.value}(execution);
        require(returnAmount > 0, "Invalid returnAmount");
        IERC20(desc.dstToken).safeApprove(address(vault), returnAmount);
    }

    function _swapSimpleMode(
        IAggregationExecutor caller,
        IKyberRouter.SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) internal returns (uint256 returnAmount, uint256 gasLeft) {
        require(desc.dstReceiver == address(this), "Invalid SwapDescription.dstReceiver");
        IERC20(desc.srcToken).safeTransferFrom(msg.sender, address(this), desc.amount);
        IERC20(desc.srcToken).safeApprove(address(kyberRouter), desc.amount);
        (returnAmount, gasLeft) = kyberRouter.swapSimpleMode(caller, desc, executorData, clientData);
        require(returnAmount > 0, "Invalid returnAmount");
        IERC20(desc.dstToken).safeApprove(address(vault), returnAmount);
    }

    function swapAndStake(
        IKyberRouter.SwapExecutionParams calldata execution
    ) external payable returns (uint256 returnAmount, uint256 gasLeft) {
        (returnAmount, gasLeft) = _swap(execution);
        vault.stake(msg.sender, address(execution.desc.dstToken), returnAmount);
    }

    function swapAndDeposit(
        IKyberRouter.SwapExecutionParams calldata execution
    ) external payable returns (uint256 returnAmount, uint256 gasLeft) {
        (returnAmount, gasLeft) = _swap(execution);
        vault.deposit(msg.sender, address(execution.desc.dstToken), returnAmount);
    }


    function swapSimpleModeAndStake(
        IAggregationExecutor caller,
        IKyberRouter.SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 gasLeft) {
        (returnAmount, gasLeft) = _swapSimpleMode(caller, desc, executorData, clientData);
        vault.stake(msg.sender, address(desc.dstToken), returnAmount);
    }

    function swapSimpleModeAndDeposit(
        IAggregationExecutor caller,
        IKyberRouter.SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 gasLeft) {
        (returnAmount, gasLeft) = _swapSimpleMode(caller, desc, executorData, clientData);
        vault.deposit(msg.sender, address(desc.dstToken), returnAmount);
    }
}

