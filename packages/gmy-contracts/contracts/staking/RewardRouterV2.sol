// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouterV2.sol";
import "./interfaces/IVester.sol";
import "./interfaces/IGmManager.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IGlpManager.sol";
import "../access/Governable.sol";

contract RewardRouterV2 is IRewardRouterV2, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public gmy;
    address public esGmy;
    address public bnGmy;

    address public glp; // GMY Liquidity Provider token
    address public gm; // GM Liquidity Provider token

    address public stakedGmyTracker;
    address public bonusGmyTracker;
    address public feeGmyTracker;

    address public override stakedGlpTracker;
    address public override stakedGmTracker;
    address public override feeGlpTracker;
    address public override feeGmTracker;

    address public glpManager;
    address public gmManager;

    address public gmyVester;
    address public glpVester;
    address public gmVester;

    mapping(address => address) public pendingReceivers;

    event StakeGmy(address account, address token, uint256 amount);
    event UnstakeGmy(address account, address token, uint256 amount);

    event StakeGlp(address account, uint256 amount);
    event StakeGm(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);
    event UnstakeGm(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address[] memory _configs
//
//        address _weth,
//        address _gmy,
//        address _esGmy,
//        address _bnGmy,
//        address _glp,
//        address _gm,
//        address _stakedGmyTracker,
//        address _bonusGmyTracker,
//        address _feeGmyTracker,
//        address _feeGlpTracker,
//        address _feeGmTracker,
//        address _stakedGlpTracker,
//        address _stakedGmTracker,
//        address _glpManager,
//        address _gmManager,
//        address _gmyVester,
//        address _glpVester,
//        address _gmVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _configs[0];

        gmy = _configs[1];
        esGmy = _configs[2];
        bnGmy = _configs[3];

        glp = _configs[4];
        gm = _configs[5];

        stakedGmyTracker = _configs[6];
        bonusGmyTracker = _configs[7];
        feeGmyTracker = _configs[8];

        feeGlpTracker = _configs[9];
        feeGmTracker = _configs[10];
        stakedGlpTracker = _configs[11];
        stakedGmTracker = _configs[12];

        glpManager = _configs[13];
        gmManager = _configs[14];

        gmyVester = _configs[15];
        glpVester = _configs[16];
        gmVester = _configs[17];
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
        _unstakeGmy(msg.sender, gmy, _amount, true);
    }

    function unstakeEsGmy(uint256 _amount) external nonReentrant {
        _unstakeGmy(msg.sender, esGmy, _amount, true);
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

    function mintAndStakeGm(address _token, uint256 _amount) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_token).safeIncreaseAllowance(gmManager, _amount);
        uint256 gmAmount = IGmManager(gmManager).stake(account, _token, _amount);
        IRewardTracker(feeGmTracker).stakeForAccount(account, account, gm, gmAmount);
        IRewardTracker(stakedGmTracker).stakeForAccount(account, account, feeGmTracker, gmAmount);

        emit StakeGm(account, gmAmount);

        return gmAmount;
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

    function unstakeAndRedeemGm(address _tokenOut, uint256 _gmAmount, uint256 _minOut) external nonReentrant returns (uint256) {
        require(_gmAmount > 0, "RewardRouter: invalid _gmAmount");

        address account = msg.sender;
        IRewardTracker(stakedGmTracker).unstakeForAccount(account, feeGmTracker, _gmAmount, account);
        IRewardTracker(feeGmTracker).unstakeForAccount(account, gm, _gmAmount, account);
        uint256 amountOut = IGmManager(gmManager).unstake(account, _tokenOut, _gmAmount);
        require(amountOut >= _minOut, "RewardRouter: invalid _minOut");
        emit UnstakeGm(account, _gmAmount);

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
        _claimEsGmy(msg.sender, msg.sender);
        _claimFees(msg.sender, msg.sender);
    }

    function claimEsGmy() external nonReentrant {
        _claimEsGmy(msg.sender, msg.sender);
    }

    function _claimEsGmy(address account, address _receiver) internal returns (uint256) {
        uint256 esGmyAmount0 = IRewardTracker(stakedGmyTracker).claimForAccount(account, _receiver);
        uint256 esGmyAmount1 = IRewardTracker(stakedGlpTracker).claimForAccount(account, _receiver);
        uint256 esGmyAmount2 = IRewardTracker(stakedGmTracker).claimForAccount(account, _receiver);
        return esGmyAmount0.add(esGmyAmount1).add(esGmyAmount2);
    }

    function claimFees() external nonReentrant {
        _claimFees(msg.sender, msg.sender);
    }

    function _claimFees(address account, address _receiver) internal returns (uint256) {
        uint256 feeAmount0 = IRewardTracker(feeGmyTracker).claimForAccount(account, _receiver);
        uint256 feeAmount1 = IRewardTracker(feeGlpTracker).claimForAccount(account, _receiver);
        uint256 feeAmount2 = IRewardTracker(feeGmTracker).claimForAccount(account, _receiver);
        return feeAmount0.add(feeAmount1).add(feeAmount2);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimGmy,
        bool _shouldStakeGmy,
        bool _shouldClaimEsGmy,
        bool _shouldStakeEsGmy,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 gmyAmount = 0;
        if (_shouldClaimGmy) {
            uint256 gmyAmount0 = IVester(gmyVester).claimForAccount(account, account);
            uint256 gmyAmount1 = IVester(glpVester).claimForAccount(account, account);
            uint256 gmyAmount2 = IVester(gmVester).claimForAccount(account, account);
            gmyAmount = gmyAmount0.add(gmyAmount1).add(gmyAmount2);
        }

        if (_shouldStakeGmy && gmyAmount > 0) {
            _stakeGmy(account, account, gmy, gmyAmount);
        }

        uint256 esGmyAmount = 0;
        if (_shouldClaimEsGmy) {
//            uint256 esGmyAmount0 = IRewardTracker(stakedGmyTracker).claimForAccount(account, account);
//            uint256 esGmyAmount1 = IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
//            uint256 esGmyAmount2 = IRewardTracker(stakedGmTracker).claimForAccount(account, account);
            esGmyAmount = _claimEsGmy(account, account);
        }

        if (_shouldStakeEsGmy && esGmyAmount > 0) {
            _stakeGmy(account, account, esGmy, esGmyAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnGmyAmount = IRewardTracker(bonusGmyTracker).claimForAccount(account, account);
            if (bnGmyAmount > 0) {
                IRewardTracker(feeGmyTracker).stakeForAccount(account, account, bnGmy, bnGmyAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
//                uint256 weth0 = IRewardTracker(feeGmyTracker).claimForAccount(account, address(this));
//                uint256 weth1 = IRewardTracker(feeGlpTracker).claimForAccount(account, address(this));
//                uint256 weth2 = IRewardTracker(feeGmTracker).claimForAccount(account, address(this));

                uint256 wethAmount = _claimFees(account, address(this)); //weth0.add(weth1).add(weth2);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
//                IRewardTracker(feeGmyTracker).claimForAccount(account, account);
//                IRewardTracker(feeGlpTracker).claimForAccount(account, account);
//                IRewardTracker(feeGmTracker).claimForAccount(account, account);
                _claimFees(account, account);

            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }


    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(gmyVester).balanceOf(msg.sender) == 0, "RewardRouter: balance > 0");
        require(IERC20(glpVester).balanceOf(msg.sender) == 0, "RewardRouter: balance > 0");
        require(IERC20(gmVester).balanceOf(msg.sender) == 0, "RewardRouter: balance > 0");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(gmyVester).balanceOf(_sender) == 0, "RewardRouter: balance > 0");
        require(IERC20(glpVester).balanceOf(_sender) == 0, "RewardRouter: balance > 0");
        require(IERC20(gmVester).balanceOf(_sender) == 0, "RewardRouter: balance > 0");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedGmy = IRewardTracker(stakedGmyTracker).depositBalances(_sender, gmy);
        if (stakedGmy > 0) {
            _unstakeGmy(_sender, gmy, stakedGmy, false);
            _stakeGmy(_sender, receiver, gmy, stakedGmy);
        }

        uint256 stakedEsGmy = IRewardTracker(stakedGmyTracker).depositBalances(_sender, esGmy);
        if (stakedEsGmy > 0) {
            _unstakeGmy(_sender, esGmy, stakedEsGmy, false);
            _stakeGmy(_sender, receiver, esGmy, stakedEsGmy);
        }

        uint256 stakedBnGmy = IRewardTracker(feeGmyTracker).depositBalances(_sender, bnGmy);
        if (stakedBnGmy > 0) {
            IRewardTracker(feeGmyTracker).unstakeForAccount(_sender, bnGmy, stakedBnGmy, _sender);
            IRewardTracker(feeGmyTracker).stakeForAccount(_sender, receiver, bnGmy, stakedBnGmy);
        }

        uint256 esGmyBalance = IERC20(esGmy).balanceOf(_sender);
        if (esGmyBalance > 0) {
            IERC20(esGmy).transferFrom(_sender, receiver, esGmyBalance);
        }

        uint256 glpAmount = IRewardTracker(feeGlpTracker).depositBalances(_sender, glp);
        if (glpAmount > 0) {
            IRewardTracker(stakedGlpTracker).unstakeForAccount(_sender, feeGlpTracker, glpAmount, _sender);
            IRewardTracker(feeGlpTracker).unstakeForAccount(_sender, glp, glpAmount, _sender);

            IRewardTracker(feeGlpTracker).stakeForAccount(_sender, receiver, glp, glpAmount);
            IRewardTracker(stakedGlpTracker).stakeForAccount(receiver, receiver, feeGlpTracker, glpAmount);
        }

        uint256 gmAmount = IRewardTracker(feeGmTracker).depositBalances(_sender, gm);
        if (gmAmount > 0) {
            IRewardTracker(stakedGmTracker).unstakeForAccount(_sender, feeGmTracker, gmAmount, _sender);
            IRewardTracker(feeGmTracker).unstakeForAccount(_sender, gm, gmAmount, _sender);

            IRewardTracker(feeGmTracker).stakeForAccount(_sender, receiver, gm, gmAmount);
            IRewardTracker(stakedGmTracker).stakeForAccount(receiver, receiver, feeGmTracker, gmAmount);
        }

        IVester(gmyVester).transferStakeValues(_sender, receiver);
        IVester(glpVester).transferStakeValues(_sender, receiver);
        IVester(gmVester).transferStakeValues(_sender, receiver);
    }

    function _validateTracker(address _tracker, address _receiver) private view {
        require(IRewardTracker(_tracker).averageStakedAmounts(_receiver) == 0, "averageStakedAmounts > 0");
        require(IRewardTracker(_tracker).cumulativeRewards(_receiver) == 0, "cumulativeRewards > 0");
    }

    function _validateVester(address _vester, address _receiver) private view {
        require(IVester(_vester).transferredAverageStakedAmounts(_receiver) == 0, "transferredAverageStakedAmounts > 0");
        require(IVester(_vester).transferredCumulativeRewards(_receiver) == 0, "transferredCumulativeRewards > 0");
    }

    function _validateReceiver(address _receiver) private view {
        _validateTracker(stakedGmyTracker, _receiver);
        _validateTracker(bonusGmyTracker, _receiver);

        _validateTracker(feeGmyTracker, _receiver);
        _validateVester(gmyVester, _receiver);
        _validateTracker(stakedGlpTracker, _receiver);

        _validateTracker(feeGlpTracker, _receiver);

        _validateVester(glpVester, _receiver);

        _validateTracker(stakedGmTracker, _receiver);

        _validateTracker(feeGmTracker, _receiver);

        _validateVester(gmVester, _receiver);

        require(IERC20(gmyVester).balanceOf(_receiver) == 0, "RewardRouter: balance > 0");
        require(IERC20(glpVester).balanceOf(_receiver) == 0, "RewardRouter: balance > 0");
        require(IERC20(gmVester).balanceOf(_receiver) == 0, "RewardRouter: balance > 0");
    }

    function _compound(address _account) private {
        _compoundGmy(_account);
        _compoundGlp(_account);
        _compoundGm(_account);
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

    function _compoundGm(address _account) private {
        uint256 esGmyAmount = IRewardTracker(stakedGmTracker).claimForAccount(_account, _account);
        if (esGmyAmount > 0) {
            _stakeGmy(_account, _account, esGmy, esGmyAmount);
        }
    }

    function _stakeGmy(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedGmyTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusGmyTracker).stakeForAccount(_account, _account, stakedGmyTracker, _amount);
        IRewardTracker(feeGmyTracker).stakeForAccount(_account, _account, bonusGmyTracker, _amount);

        emit StakeGmy(_account, _token, _amount);
    }

    function _unstakeGmy(address _account, address _token, uint256 _amount, bool _shouldReduceBnGmy) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedGmyTracker).stakedAmounts(_account);

        IRewardTracker(feeGmyTracker).unstakeForAccount(_account, bonusGmyTracker, _amount, _account);
        IRewardTracker(bonusGmyTracker).unstakeForAccount(_account, stakedGmyTracker, _amount, _account);
        IRewardTracker(stakedGmyTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnGmy) {
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
        }

        emit UnstakeGmy(_account, _token, _amount);
    }
}
