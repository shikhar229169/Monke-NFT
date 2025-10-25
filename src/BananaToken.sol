// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MonkeyNft} from "./MonkeyNft.sol";

contract BananaToken is ERC20 {
    error BananaToken__NotMonkeyNftOwner();

    struct StakingStats {
        uint256 stakeTime;
        uint256 bananaFarmed;
        address owner;
    }

    address immutable public monkeyNft;
    uint256 public s_totalBananaFarmed;
    mapping(uint256 tokenId => StakingStats) public s_monkeyStakingStats;

    constructor(address _monkeyNft) ERC20("BananaToken", "BTKN") {
        monkeyNft = _monkeyNft;
    }

    function stakeMonkey(uint256 tokenId) external {
        address nftOwner = MonkeyNft(monkeyNft).ownerOf(tokenId);
        require(msg.sender == nftOwner, BananaToken__NotMonkeyNftOwner());

        MonkeyNft(monkeyNft).safeTransferFrom(msg.sender, address(this), tokenId);
        s_monkeyStakingStats[tokenId] = StakingStats({
            stakeTime: block.timestamp,
            bananaFarmed: 0,
            owner: msg.sender
        });
    }
}