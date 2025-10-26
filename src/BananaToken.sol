// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MonkeyNft} from "./MonkeyNft.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract BananaToken is ERC20, IERC721Receiver {
    error BananaToken__NotMonkeyNftOwner();
    error BananaToken__MonkeyNotStaked();
    error BananaToken__CalledNotActualMonkeyOwner();
    error BananaToken__OnlyFarmerMonkeysCanStake();

    struct StakingStats {
        uint256 stakeTime;
        uint256 latestClaimTime;
        uint256 bananaFarmed;
        address owner;
    }

    address immutable public monkeyNft;
    uint256 public s_totalBananaFarmed;
    uint256 public minStakingTime = 1 days;
    uint256 public constant ONE_DAY = 1 days;
    uint256 public perDayReward = 100e18;
    mapping(uint256 tokenId => StakingStats) public s_monkeyStakingStats;

    event MonkeyNftStaked(address owner, uint256 tokenId);
    event MonkeyNftUnstaked(address owner, uint256 tokenId);
    event BananasFarmed(address owner, uint256 amount);

    constructor(address _monkeyNft) ERC20("BananaToken", "BTKN") {
        monkeyNft = _monkeyNft;
    }

    function stakeMonkey(uint256 tokenId) external {
        MonkeyNft.MonkeyTraits memory monkeyTraits = MonkeyNft(monkeyNft).getMonkeyInfo(tokenId);
        require(monkeyTraits.monkeyType == MonkeyNft.MonkeyType.FARMER, BananaToken__OnlyFarmerMonkeysCanStake());
        address nftOwner = MonkeyNft(monkeyNft).ownerOf(tokenId);
        require(msg.sender == nftOwner, BananaToken__NotMonkeyNftOwner());

        MonkeyNft(monkeyNft).safeTransferFrom(msg.sender, address(this), tokenId);
        s_monkeyStakingStats[tokenId] = StakingStats({
            stakeTime: block.timestamp,
            latestClaimTime: block.timestamp,
            bananaFarmed: 0,
            owner: msg.sender
        });

        emit MonkeyNftStaked(msg.sender, tokenId);
    }

    function collectFarmedBananas(uint256 tokenId) external {
        _updateFarmedBananas(tokenId);
    }

    function unstakeMonkey(uint256 tokenId) external {
        require(msg.sender == s_monkeyStakingStats[tokenId].owner, BananaToken__CalledNotActualMonkeyOwner());
        _updateFarmedBananas(tokenId);
        s_monkeyStakingStats[tokenId].owner = address(0);
        s_monkeyStakingStats[tokenId].stakeTime = 0;
        s_monkeyStakingStats[tokenId].latestClaimTime = 0;
        MonkeyNft(monkeyNft).safeTransferFrom(address(this), msg.sender, tokenId);

        emit MonkeyNftUnstaked(msg.sender, tokenId);
    }

    function _updateFarmedBananas(uint256 tokenId) internal {
        require(s_monkeyStakingStats[tokenId].owner != address(0), BananaToken__MonkeyNotStaked());
        uint256 timeStaked = block.timestamp - s_monkeyStakingStats[tokenId].latestClaimTime;
        if (timeStaked >= minStakingTime) {
            s_monkeyStakingStats[tokenId].latestClaimTime = block.timestamp;
            uint256 bananasToFarm = (timeStaked / ONE_DAY) * perDayReward;
            s_monkeyStakingStats[tokenId].bananaFarmed += bananasToFarm;
            s_totalBananaFarmed += bananasToFarm;
            _mint(s_monkeyStakingStats[tokenId].owner, bananasToFarm);
            emit BananasFarmed(msg.sender, bananasToFarm);
        }
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getMonkeyStakingStats(uint256 tokenId) external view returns (StakingStats memory) {
        return s_monkeyStakingStats[tokenId];
    }
}
