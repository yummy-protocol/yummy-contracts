// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MintableBaseToken.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/ISettingsManager.sol";

contract GM is MintableBaseToken {
    IVault public vault;
    ISettingsManager public settingsManager;
    address public gov;

    mapping(address => bool) public isHandler;


    constructor() MintableBaseToken("GM", "GM", 0) {
        gov = msg.sender;
    }
    modifier onlyGov() {
        require(msg.sender == gov, "GM: forbidden");
        _;
    }
    function initialize(address _vault, address _settingsManager) external onlyOwner {
        vault = IVault(_vault);
        settingsManager = ISettingsManager(_settingsManager);
        transferOwnership(_vault);
    }

    function id() external pure returns (string memory _name) {
        return "GM";
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        require(
            vault.lastStakedAt(msg.sender) + settingsManager.cooldownDuration() <= block.timestamp,
            "GM: cooldown duration not yet passed"
        );
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }
        if (!settingsManager.isWhitelistedFromTransferCooldown(_recipient)) {
            require(
                vault.lastStakedAt(_sender) + settingsManager.cooldownDuration() <= block.timestamp,
                "GM: cooldown duration not yet passed"
            );
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }
}
