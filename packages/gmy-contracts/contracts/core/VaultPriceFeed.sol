// SPDX-License-Identifier: MIT


import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/ISecondaryPriceFeed.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "../access/Governable.sol";

pragma solidity ^0.8.0;

contract VaultPriceFeed is IVaultPriceFeed, Governable {

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;

    bool public isSecondaryPriceEnabled = true;
    bool public favorPrimaryPrice = false;
    uint256 public maxStrictPriceDeviation = 10000000000000000000000000000;
    address public secondaryPriceFeed;
    uint256 public spreadThresholdBasisPoints = 30;

    address public pythNetwork;

    mapping(address => uint256) public spreadBasisPoints;
    mapping(address => bytes32) public priceFeeds;
    mapping(address => uint256) public allowedStaleness;
    // Pyth can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping(address => bool) public strictStableTokens;

    mapping(address => uint256) public override adjustmentBasisPoints;
    mapping(address => bool) public override isAdjustmentAdditive;
    mapping(address => uint256) public lastAdjustmentTimings;

    constructor() public {
    }
    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyGov {
        require(
            lastAdjustmentTimings[_token] + MAX_ADJUSTMENT_INTERVAL < block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setPythNetwork(address _pythNetwork) external onlyGov {
        pythNetwork = _pythNetwork;
    }

    function setIsSecondaryPriceEnabled(bool _isEnabled) external override onlyGov {
        isSecondaryPriceEnabled = _isEnabled;
    }

    function setSecondaryPriceFeed(address _secondaryPriceFeed) external onlyGov {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyGov {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external override onlyGov {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external override onlyGov {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external override onlyGov {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }


    function setTokenConfig(
        address _token,
        bytes32 _priceFeed,
        uint256 _allowedStaleness,
        bool _isStrictStable
    ) external onlyGov {
        strictStableTokens[_token] = _isStrictStable;
        priceFeeds[_token] = _priceFeed;
        allowedStaleness[_token] = _allowedStaleness;
    }

    function getPrice(address _token, bool _maximise, bool /*_includeAmmPrice*/, bool /*_useSwapPricing*/) public override view returns (uint256) {
        uint256 price = getPriceV1(_token, _maximise);

        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price = price * (BASIS_POINTS_DIVISOR + adjustmentBps) / BASIS_POINTS_DIVISOR;
            } else {
                price = price * (BASIS_POINTS_DIVISOR - adjustmentBps) / BASIS_POINTS_DIVISOR;
            }
        }

        return price;
    }

    function getPriceV1(address _token, bool _maximise) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (isSecondaryPriceEnabled && !strictStableTokens[_token]) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price - ONE_USD : ONE_USD - price;
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price * (BASIS_POINTS_DIVISOR + _spreadBasisPoints) / BASIS_POINTS_DIVISOR;
        }

        return price * (BASIS_POINTS_DIVISOR - _spreadBasisPoints) / BASIS_POINTS_DIVISOR;
    }

    function getLatestPrimaryPrice(address _token) public override view returns (uint256) {
        return _getPythPrice(_token, true, false, true);
    }

    function getPrimaryPrice(address _token, bool _maximise) public override view returns (uint256) {
        return _getPythPrice(_token, false, _maximise, true);
    }

    function getPythPrice(address _token) external view returns (uint256) {
        return _getPythPrice(_token, true, true, false);
    }

    function _getPythPrice(address _token, bool _ignoreConfidence, bool _maximise, bool _requireFreshness) internal view returns (uint256) {
        PythStructs.Price memory priceData = _getPythPriceData(_token);
        if (_requireFreshness && allowedStaleness[_token] > 0) {
            require(block.timestamp <= priceData.publishTime + allowedStaleness[_token], "VaultPriceFeed: price stale");
        }
        uint256 price;
        if (_ignoreConfidence) {
            price = uint256(uint64(priceData.price));
        } else {
            uint256 scaledConf = uint256(uint64(priceData.conf));
            price = _maximise ? uint256(uint64(priceData.price)) + scaledConf : uint256(uint64(priceData.price)) - scaledConf;
        }
        require(priceData.expo <= 0, "VaultPriceFeed: invalid price exponent");
        uint32 priceExponent = uint32(- priceData.expo);
        return price * PRICE_PRECISION / (10 ** priceExponent);
    }

    function _getPythPriceData(address _token) internal view returns (PythStructs.Price memory) {
        require(address(pythNetwork) != address(0), "VaultPriceFeed: pyth network address is not configured");
        bytes32 id = priceFeeds[_token];
        require(id != bytes32(0), "VaultPriceFeed: price id not configured for given token");
        PythStructs.Price memory priceData = IPyth(pythNetwork).getEmaPriceUnsafe(id);
        require(priceData.price > 0, "VaultPriceFeed: invalid price");
        return priceData;
    }

    function getSecondaryPrice(address _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) {return _referencePrice;}
        return ISecondaryPriceFeed(secondaryPriceFeed).getPrice(_token, _referencePrice, _maximise);
    }

}