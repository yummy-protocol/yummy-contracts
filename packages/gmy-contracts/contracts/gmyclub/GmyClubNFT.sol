// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IGmyClubNFT.sol";

contract GmyClubNFT is ERC721Enumerable, Ownable, ReentrancyGuard, IGmyClubNFT {

    string private _baseTokenURI;

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    /// @notice Collection of NFT details to describe each NFT
    struct NFTDetails {
        uint256 power;
    }
    /// @notice Use the NFT tokenId to read NFT details
    mapping(uint256 => NFTDetails) public nftDetailsById;
    address public saleContract;
    constructor(address _saleContract) ERC721("GMYC", "GmyClub NFT") {
        saleContract = _saleContract;
    }


    /* ========== Public view functions ========== */

    function getTokenPower(uint256 tokenId) external view returns (uint256) {
        NFTDetails memory currentNFTDetails = nftDetailsById[tokenId];
        return currentNFTDetails.power;
    }

    // @dev sets base URI
    function setBaseURI(string memory _uri) external onlyOwner {
        _baseTokenURI = _uri;
    }
    /**
 * @dev Throws if called by any account other than the saleContract.
     */
    modifier onlySaleContract() {
        require(saleContract == _msgSender(), "GmyNFT: caller is not the saleContract");
        _;
    }

    function mint(uint256 _power, address _to) external onlySaleContract returns (uint256) {
        uint256 id = totalSupply() + 1;
        nftDetailsById[id] = NFTDetails(_power);
        _mint(_to, id);
        return id;
    }
}