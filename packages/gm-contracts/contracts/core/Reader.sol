// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IOrderVault.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ISettingsManager.sol";

import {Constants} from "../access/Constants.sol";
import {OrderStatus, PositionTrigger, TriggerInfo, PaidFees} from "./structs.sol";

contract Reader is Constants, Initializable {
    struct AccruedFees {
        uint256 positionFee;
        uint256 borrowFee;
        int256 fundingFee;
    }

    IOrderVault private orderVault;
    IPositionVault private positionVault;
    ISettingsManager private settingsManager;
    IVault private vault;
    IERC20 private USDC;
    IERC20 private gusd;
    IERC20 private gm;

    function initialize(IPositionVault _positionVault, IOrderVault _orderVault, ISettingsManager _settingsManager) public initializer {
        require(AddressUpgradeable.isContract(address(_positionVault)), "positionVault invalid");
        require(AddressUpgradeable.isContract(address(_orderVault)), "orderVault invalid");
        positionVault = _positionVault;
        orderVault = _orderVault;
        settingsManager = _settingsManager;
    }


    function initializeV2(IVault _vault, IERC20 _USDC, IERC20 _gusd, IERC20 _gm) reinitializer(2) public {
        require(AddressUpgradeable.isContract(address(_vault)), "Vault invalid");
        require(AddressUpgradeable.isContract(address(_gm)), "gm invalid");
        require(AddressUpgradeable.isContract(address(_USDC)), "USDC invalid");
        require(AddressUpgradeable.isContract(address(_gusd)), "gusd invalid");
        vault = _vault;
        gm = _gm;
        USDC = _USDC;
        gusd = _gusd;
    }

    function getUserAlivePositions(
        address _user
    )
    public
    view
    returns (uint256[] memory, Position[] memory, Order[] memory, PositionTrigger[] memory, PaidFees[] memory, AccruedFees[] memory)
    {
        uint256[] memory posIds = positionVault.getUserPositionIds(_user);
        return getPositions(posIds);
    }

    function getPositions(
        uint256[] memory posIds
    )
    public
    view
    returns (uint256[] memory, Position[] memory, Order[] memory, PositionTrigger[] memory, PaidFees[] memory, AccruedFees[] memory)
    {
        uint256 length = posIds.length;
        Position[] memory positions_ = new Position[](length);
        Order[] memory orders_ = new Order[](length);
        PositionTrigger[] memory triggers_ = new PositionTrigger[](length);
        PaidFees[] memory paidFees_ = new PaidFees[](length);
        AccruedFees[] memory accruedFees_ = new AccruedFees[](length);
        for (uint i; i < length; ++i) {
            uint256 posId = posIds[i];
            positions_[i] = positionVault.getPosition(posId);
            orders_[i] = orderVault.getOrder(posId);
            triggers_[i] = orderVault.getTriggerOrderInfo(posId);
            paidFees_[i] = positionVault.getPaidFees(posId);
            accruedFees_[i] = getAccruedFee(posId);
        }
        return (posIds, positions_, orders_, triggers_, paidFees_, accruedFees_);
    }
    function getAccruedFee(uint256 _posId) internal view returns (AccruedFees memory){
        Position memory position = positionVault.getPosition(_posId);
        AccruedFees memory accruedFees;
        accruedFees.positionFee = settingsManager.getTradingFee(position.owner, position.tokenId, position.isLong, position.size);
        accruedFees.borrowFee = settingsManager.getBorrowFee(position.size, position.lastIncreasedTime, position.tokenId, position.isLong) + position.accruedBorrowFee;
        accruedFees.fundingFee = settingsManager.getFundingFee(position.tokenId, position.isLong, position.size, position.fundingIndex);
        return accruedFees;
    }

    function getGlobalInfo(
        address _account,
        uint256 _tokenId
    )
    external
    view
    returns (
        int256 fundingRate,
        uint256 borrowRateForLong,
        uint256 borrowRateForShort,
        uint256 longOpenInterest,
        uint256 shortOpenInterest,
        uint256 maxLongOpenInterest,
        uint256 maxShortOpenInterest,
        uint256 longTradingFee,
        uint256 shortTradingFee
    )
    {
        fundingRate = settingsManager.getFundingRate(_tokenId);
        borrowRateForLong = settingsManager.getBorrowRate(_tokenId, true);
        borrowRateForShort = settingsManager.getBorrowRate(_tokenId, false);
        longOpenInterest = settingsManager.openInterestPerAssetPerSide(_tokenId, true);
        shortOpenInterest = settingsManager.openInterestPerAssetPerSide(_tokenId, false);
        maxLongOpenInterest = settingsManager.maxOpenInterestPerAssetPerSide(_tokenId, true);
        maxShortOpenInterest = settingsManager.maxOpenInterestPerAssetPerSide(_tokenId, false);
        longTradingFee = settingsManager.getTradingFee(_account, _tokenId, true, PRICE_PRECISION);
        shortTradingFee = settingsManager.getTradingFee(_account, _tokenId, false, PRICE_PRECISION);
    }

    function getUserOpenOrders(
        address _user
    )
    public
    view
    returns (uint256[] memory, Position[] memory, Order[] memory, PositionTrigger[] memory, PaidFees[] memory, AccruedFees[] memory)
    {
        uint256[] memory posIds = positionVault.getUserOpenOrderIds(_user);
        uint256 length = posIds.length;
        Position[] memory positions_ = new Position[](length);
        Order[] memory orders_ = new Order[](length);
        PositionTrigger[] memory triggers_ = new PositionTrigger[](length);
        PaidFees[] memory paidFees_ = new PaidFees[](length);
        AccruedFees[] memory accruedFees_ = new AccruedFees[](length);
        for (uint i; i < length; ++i) {
            uint256 posId = posIds[i];
            positions_[i] = positionVault.getPosition(posId);
            orders_[i] = orderVault.getOrder(posId);
            triggers_[i] = orderVault.getTriggerOrderInfo(posId);
            paidFees_[i] = positionVault.getPaidFees(posId);
            accruedFees_[i] = getAccruedFee(posId);
        }
        return (posIds, positions_, orders_, triggers_, paidFees_, accruedFees_);
    }

    function getFeesFor1CT(address _normal, address _oneCT) external view returns (bool, uint256) {
        uint256 tierInfoPercent = settingsManager.getTierInfo(_normal);
        uint256 deductFeePercentForNormal = settingsManager.deductFeePercent(_normal);
        uint256 deductFeePercentForOneCT = settingsManager.deductFeePercent(_oneCT);
        if (tierInfoPercent * (BASIS_POINTS_DIVISOR - deductFeePercentForNormal) / BASIS_POINTS_DIVISOR != (BASIS_POINTS_DIVISOR - deductFeePercentForOneCT)) {
            return (true, BASIS_POINTS_DIVISOR - tierInfoPercent * (BASIS_POINTS_DIVISOR - deductFeePercentForNormal) / BASIS_POINTS_DIVISOR);
        } else {
            return (false, 0);
        }
    }

    function validateMaxOILimit(address _account, bool _isLong, uint256 _size, uint256 _tokenId) external view returns (uint256, uint256, uint256, uint8) {
        uint256 _openInterestPerUser = settingsManager.openInterestPerUser(_account);
        uint256 _maxOpenInterestPerUser = settingsManager.maxOpenInterestPerUser(_account);
        uint256 tradingFee = settingsManager.getTradingFee(_account, _tokenId, _isLong, _size);
        uint256 triggerGasFee = settingsManager.triggerGasFee();
        uint256 marketOrderGasFee = settingsManager.marketOrderGasFee();
        if (_maxOpenInterestPerUser == 0) _maxOpenInterestPerUser = settingsManager.defaultMaxOpenInterestPerUser();
        if (_openInterestPerUser + _size > _maxOpenInterestPerUser)
            return (triggerGasFee, marketOrderGasFee, tradingFee, 1);
        uint256 _openInterestPerAssetPerSide = settingsManager.openInterestPerAssetPerSide(_tokenId, _isLong);
        if (_openInterestPerAssetPerSide + _size > settingsManager.maxOpenInterestPerAssetPerSide(_tokenId, _isLong ))
            return (triggerGasFee, marketOrderGasFee, tradingFee, 2);
        return (triggerGasFee, marketOrderGasFee, tradingFee, 0);
    }

    function getUserBalances(address _account) external view returns (uint256 ethBalance, uint256 usdcBalance, uint256 usdcAllowance, uint256 gusdBalance) {
        ethBalance = _account.balance;
        usdcBalance = USDC.balanceOf(_account);
        usdcAllowance = USDC.allowance(_account, address(vault));
        gusdBalance = gusd.balanceOf(_account);
    }
}
