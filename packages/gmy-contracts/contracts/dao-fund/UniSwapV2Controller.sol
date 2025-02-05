// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IUniSwapV2Router.sol";
import "./ISwapController.sol";


contract UniSwapV2Controller is ISwapController {
    using SafeERC20 for IERC20;



    address public router;
    address public gov;
    mapping(address => address[]) public paths;


    constructor(address _router) public {
        router = _router;
        gov = msg.sender;
    }
    modifier onlyGov() {
        require(msg.sender == gov, "FeeController: forbidden");
        _;
    }
    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }


    function setPathsRoutes(
        address _token,
        address[] calldata _routes
    ) external onlyGov {
        address[] storage routes = paths[_token];
        for (uint i = 0; i < routes.length; i++) {
            routes.pop();
        }
        for (uint i = 0; i < _routes.length; i++) {
            routes.push(_routes[i]);
        }
    }


    function swap(address _token, uint256 amount, uint256 minAmount, address to) override external {
        IERC20(_token).approve(router, amount);
        IUniSwapV2Router(router).swapExactTokensForTokens(amount, minAmount, paths[_token], to, block.timestamp);
    }


    function governanceRecoverUnsupported(IERC20 _token) external onlyGov {
        _token.transfer(gov, _token.balanceOf(address(this)));
    }
}
