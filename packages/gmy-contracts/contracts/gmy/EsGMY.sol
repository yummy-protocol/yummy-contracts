// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract EsGMY is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed GMY", "esGMY", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "esGMY";
    }
}
