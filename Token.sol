//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IToken is IERC721 {
    function isFirstSaleAdmin(address sender) external view returns (bool);

    function mintTo(address recipient, uint256 id) external;
}

contract Token is Ownable, ERC721, IToken {
    address fs;

    constructor(string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
    {}

    function isFirstSaleAdmin(address sender)
        external
        view
        override
        returns (bool)
    {
        return sender == owner();
    }

    function mintTo(address recipient, uint256 id) external override {
        address sender = _msgSender();
        require(sender == firstSaleStorefront || sender == owner(), ""); //todo

        _mint(recipient, id);
    }

    function setFS(address fs_) external onlyOwner {
        fs = fs_;
    }
}
