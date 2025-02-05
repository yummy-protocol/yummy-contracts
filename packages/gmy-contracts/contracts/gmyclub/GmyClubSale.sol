// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IVester.sol";
import "./GmyClubNFT.sol";

contract GmyClubSale is Ownable, ReentrancyGuard {

    uint256 public constant MAX_GMYC_PURCHASE = 20; // max purchase per txn
    uint256 public constant MAX_GMYC = 5000; // max of 5000

    // State variables
    address public communityFund;
    address public gmyVester;
    address public esGMY;
    GmyClubNFT public gmyClubNFT;

    string public GMYC_PROVENANCE = "";
    uint256 public gmycPrice = 75000000000000000 ; // 0.075 ETH
    uint256 public gmycPower = 5000; // 5000 power
    uint256 public esGMYBonus = 40e18; // 40 esGMY
    uint256 public totalVolume;
    uint256 public totalPower;
    uint256 public totalBonus;

    uint256 public stepEsGMY = 10000; // 1.00
    uint256 public stepPrice = 10000; // 1.00
    uint256 public stepPower = 9900; // 0.99
    uint256 public step = 100; //

    bool public saleIsActive = false; // determines whether sales is active

    event AssetMinted(address account, uint256 tokenId, uint256 power, uint256 bonus);

    constructor(address _communityFund, address _esGMY, address _gmyVester) {
        gmyClubNFT = new GmyClubNFT(address(this));
        communityFund = _communityFund;
        esGMY = _esGMY;
        gmyVester = _gmyVester;
        gmyClubNFT.transferOwnership(msg.sender);
    }


    // get current price and power
    function getCurrentPP() public view returns (uint256 _gmycPrice, uint256 _gmycPower, uint256 _esGMYBonus) {
        _gmycPrice = gmycPrice;
        _gmycPower = gmycPower;
        _esGMYBonus = esGMYBonus;
        uint256 _totalSupply = gmyClubNFT.totalSupply();
        uint256 modulus = gmyClubNFT.totalSupply() % step;
        if (modulus == 0 && _totalSupply != 0) {
            _gmycPrice = (gmycPrice * stepPrice) / 10000;
            _gmycPower = (gmycPower * stepPower) / 10000;
            _esGMYBonus = (esGMYBonus * stepEsGMY) / 10000;
        }
    }

    /* ========== External public sales functions ========== */

    // @dev mints meerkat for the general public
    function mintGmyClub(uint256 numberOfTokens) external payable nonReentrant returns (uint256 _totalPrice, uint256 _totalPower, uint256 _totalBonus) {
        require(saleIsActive, 'Sale Is Not Active');
        // Sale must be active
        require(numberOfTokens <= MAX_GMYC_PURCHASE, 'Exceed Purchase');
        // Max mint of 1
        require(gmyClubNFT.totalSupply() + numberOfTokens <= MAX_GMYC);
        for (uint i = 0; i < numberOfTokens; i++) {
            if (gmyClubNFT.totalSupply() < MAX_GMYC) {
                (gmycPrice, gmycPower, esGMYBonus) = this.getCurrentPP();
                _totalPrice = _totalPrice + gmycPrice;
                uint256 id = gmyClubNFT.mint(gmycPower, msg.sender);
                emit AssetMinted(msg.sender, id, gmycPower, esGMYBonus);
                IERC20(esGMY).transfer(msg.sender, esGMYBonus);
                IVester vester = IVester(gmyVester);
                vester.setBonusRewards(msg.sender, vester.bonusRewards(msg.sender) + esGMYBonus);
                _totalPower += gmycPower;
                _totalBonus += esGMYBonus;
            }
        }
        require(_totalPrice <= msg.value);
        if (msg.value > _totalPrice) {
            payable(msg.sender).transfer(msg.value - _totalPrice);
        }
        payable(communityFund).transfer(_totalPrice);
        totalVolume += _totalPrice;
        totalBonus += _totalBonus;
        totalPower += _totalPower;
    }

    function estimateAmount(uint256 numberOfTokens) external view returns (uint256 _totalPrice, uint256 _totalPower, uint256 _totalBonus) {
        uint256 _price = gmycPrice;
        uint256 _power = gmycPower;
        uint256 _bonus = esGMYBonus;
        uint256 _totalSupply = gmyClubNFT.totalSupply();
        for (uint i = 0; i < numberOfTokens; i++) {
            if (_totalSupply < MAX_GMYC) {
                if (_totalSupply % step == 0 && _totalSupply != 0) {
                    _price = (_price * stepPrice) / 10000;
                    _power = (_power * stepPower) / 10000;
                    _bonus = (_bonus * stepEsGMY) / 10000;
                }
                _totalPrice += _price;
                _totalPower += _power;
                _totalBonus += _bonus;
                _totalSupply = _totalSupply + 1;
            } else {
                break;
            }
        }
    }


    // @dev withdraw funds
    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    // @dev withdraw funds
    function withdrawERC20(address token) external onlyOwner {
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }

    // @dev flips the state for sales
    function flipSaleState() external onlyOwner {
        saleIsActive = !saleIsActive;
    }


    // @dev set insurance fund contract address
    function setCommunityFund(address _communityFund) public onlyOwner {
        communityFund = _communityFund;
    }
    // @dev set esGMY contract address
    function setEsGMY(address _esGMY) public onlyOwner {
        esGMY = _esGMY;
    }
    // @dev set gmyVester contract address
    function setGmyVester(address _gmyVester) public onlyOwner {
        gmyVester = _gmyVester;
    }

    // @dev sets sale info (price + power)
    function setSaleInfo(uint256 _price, uint256 _power, uint256 _esGMYBonus) external onlyOwner {
        gmycPrice = _price;
        gmycPower = _power;
        esGMYBonus = _esGMYBonus;
    }

    // @dev set increate Price And Power
    function setIncreaseInfo(uint256 _stepPrice, uint256 _stepPower, uint256 _step, uint256 _stepEsGMY) public onlyOwner {
        stepPrice = _stepPrice;
        stepPower = _stepPower;
        step = _step;
        stepEsGMY = _stepEsGMY;
    }


    // @dev set provenance once it's calculated
    function setProvenanceHash(string memory provenanceHash) public onlyOwner {
        GMYC_PROVENANCE = provenanceHash;
    }
}