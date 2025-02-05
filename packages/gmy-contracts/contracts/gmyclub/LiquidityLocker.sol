pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LiquidityLocker {
    using SafeERC20 for IERC20;
    address public  immutable timelock;
    address public  immutable lockToken;
    uint256 public lockUntil;
    uint256 public constant  MAX_INCREASE_LOCK = 180 days;

    constructor(address _timelock, address _lockToken, uint256 _lockUntil){
        timelock = _timelock;
        lockToken = _lockToken;
        lockUntil = _lockUntil;
    }
    function increaseLock(uint256 _duration) external {
        require(_duration < MAX_INCREASE_LOCK, "LiquidityLocker: duration too long");
        require(timelock == msg.sender, "LiquidityLocker: !timelock");
        lockUntil += _duration;
    }

    function skim(address _token, uint256 _amount, address _to) external {
        require(timelock == msg.sender, "LiquidityLocker: !timelock");
        require(_token != lockToken || block.timestamp >= lockUntil, "LiquidityLocker: still locked");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}