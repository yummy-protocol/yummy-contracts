// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IGlpManager.sol";
import "../access/Governable.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public gmy;
    address public esGmy;
    address public bnGmy;

    address public glp; // GMY Liquidity Provider token

    address public stakedGmyTracker;
    address public bonusGmyTracker;
    address public feeGmyTracker;

    address public stakedGlpTracker;
    address public feeGlpTracker;

    address public glpManager;

    event StakeGmy(address account, uint256 amount);
    event UnstakeGmy(address account, uint256 amount);

    event StakeGlp(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _gmy,
        address _esGmy,
        address _bnGmy,
        address _glp,
        address _stakedGmyTracker,
        address _bonusGmyTracker,
        address _feeGmyTracker,
        address _feeGlpTracker,
        address _stakedGlpTracker,
        address _glpManager
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        gmy = _gmy;
        esGmy = _esGmy;
        bnGmy = _bnGmy;

        glp = _glp;

        stakedGmyTracker = _stakedGmyTracker;
        bonusGmyTracker = _bonusGmyTracker;
        feeGmyTracker = _feeGmyTracker;

        feeGlpTracker = _feeGlpTracker;
        stakedGlpTracker = _stakedGlpTracker;

        glpManager = _glpManager;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeGmyForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _gmy = gmy;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeGmy(msg.sender, _accounts[i], _gmy, _amounts[i]);
        }
    }

    function stakeGmyForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeGmy(msg.sender, _account, gmy, _amount);
    }

    function stakeGmy(uint256 _amount) external nonReentrant {
        _stakeGmy(msg.sender, msg.sender, gmy, _amount);
    }

    function stakeEsGmy(uint256 _amount) external nonReentrant {
        _stakeGmy(msg.sender, msg.sender, esGmy, _amount);
    }

    function unstakeGmy(uint256 _amount) external nonReentrant {
        _unstakeGmy(msg.sender, gmy, _amount);
    }

    function unstakeEsGmy(uint256 _amount) external nonReentrant {
        _unstakeGmy(msg.sender, esGmy, _amount);
    }

    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minGlp);
        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(glpManager, msg.value);

        address account = msg.sender;
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsdg, _minGlp);

        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(account, _tokenOut, _glpAmount, _minOut, _receiver);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(account, weth, _glpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeGmyTracker).claimForAccount(account, account);
        IRewardTracker(feeGlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedGmyTracker).claimForAccount(account, account);
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimEsGmy() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedGmyTracker).claimForAccount(account, account);
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeGmyTracker).claimForAccount(account, account);
        IRewardTracker(feeGlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function _compound(address _account) private {
        _compoundGmy(_account);
        _compoundGlp(_account);
    }

    function _compoundGmy(address _account) private {
        uint256 esGmyAmount = IRewardTracker(stakedGmyTracker).claimForAccount(_account, _account);
        if (esGmyAmount > 0) {
            _stakeGmy(_account, _account, esGmy, esGmyAmount);
        }

        uint256 bnGmyAmount = IRewardTracker(bonusGmyTracker).claimForAccount(_account, _account);
        if (bnGmyAmount > 0) {
            IRewardTracker(feeGmyTracker).stakeForAccount(_account, _account, bnGmy, bnGmyAmount);
        }
    }

    function _compoundGlp(address _account) private {
        uint256 esGmyAmount = IRewardTracker(stakedGlpTracker).claimForAccount(_account, _account);
        if (esGmyAmount > 0) {
            _stakeGmy(_account, _account, esGmy, esGmyAmount);
        }
    }

    function _stakeGmy(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedGmyTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusGmyTracker).stakeForAccount(_account, _account, stakedGmyTracker, _amount);
        IRewardTracker(feeGmyTracker).stakeForAccount(_account, _account, bonusGmyTracker, _amount);

        emit StakeGmy(_account, _amount);
    }

    function _unstakeGmy(address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedGmyTracker).stakedAmounts(_account);

        IRewardTracker(feeGmyTracker).unstakeForAccount(_account, bonusGmyTracker, _amount, _account);
        IRewardTracker(bonusGmyTracker).unstakeForAccount(_account, stakedGmyTracker, _amount, _account);
        IRewardTracker(stakedGmyTracker).unstakeForAccount(_account, _token, _amount, _account);

        uint256 bnGmyAmount = IRewardTracker(bonusGmyTracker).claimForAccount(_account, _account);
        if (bnGmyAmount > 0) {
            IRewardTracker(feeGmyTracker).stakeForAccount(_account, _account, bnGmy, bnGmyAmount);
        }

        uint256 stakedBnGmy = IRewardTracker(feeGmyTracker).depositBalances(_account, bnGmy);
        if (stakedBnGmy > 0) {
            uint256 reductionAmount = stakedBnGmy.mul(_amount).div(balance);
            IRewardTracker(feeGmyTracker).unstakeForAccount(_account, bnGmy, reductionAmount, _account);
            IMintable(bnGmy).burn(_account, reductionAmount);
        }

        emit UnstakeGmy(_account, _amount);
    }
}
