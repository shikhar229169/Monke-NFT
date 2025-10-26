// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {MonkeyNft} from "../src/MonkeyNft.sol"; 
import {BananaToken} from "../src/BananaToken.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockLinkToken} from "chainlink-brownie-contracts/contracts/src/v0.8/mocks/MockLinkToken.sol";

contract MonkeyNftTest is Test {
    MonkeyNft private monkeyNft;
    BananaToken private bananaToken;
    VRFCoordinatorV2_5Mock private vrfCoordinator;
    MockLinkToken private linkToken;
    address owner;
    uint256 subId;
    
    function setUp() external {
        owner = makeAddr("owner");     
        linkToken = new MockLinkToken();
        vrfCoordinator = new VRFCoordinatorV2_5Mock(10, 10, 100000000000);
        
        subId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subId, 10e18);
        
        // VRF Config
        MonkeyNft.VrfConfig memory vrfConfig = MonkeyNft.VrfConfig({
            keyHash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979f7e4d5e5c8d6,
            subId: subId,
            requestConfirmations: 3,
            callbackGasLimit: 500000,
            numWords: 1,
            enableNativePayment: false
        });
        
        monkeyNft = new MonkeyNft(address(vrfCoordinator), vrfConfig, address(linkToken));
        bananaToken = new BananaToken(address(monkeyNft));
        monkeyNft.setBananaTokenAddress(address(bananaToken));

        // add consumer monkey nft to vrf subscription
        vrfCoordinator.addConsumer(subId, address(monkeyNft));
    }

    function testInitialSetup() external view {
        MonkeyNft.VrfConfig memory vrfConfig = monkeyNft.getVrfConfig();
        bool consumerAdded = vrfCoordinator.consumerIsAdded(subId, address(monkeyNft));
        
        assert(consumerAdded);
        assertEq(address(monkeyNft.s_vrfCoordinator()), address(vrfCoordinator));
        assertEq(vrfConfig.subId, subId);
    }

    function testRequestMonkeyNftMint() external {
        address user = makeAddr("user");
        vm.prank(user);
        uint256 requestId = monkeyNft.requestMintMonkeyNft();
        assert(requestId > 0);
        assertEq(monkeyNft.s_mintRequests(requestId), user);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 778;
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(monkeyNft), randomWords);
        assertEq(monkeyNft.s_mintRequests(requestId), address(0));

        MonkeyNft.MonkeyTraits memory traits = monkeyNft.getMonkeyInfo(1);
        uint256[] memory tokenIds = monkeyNft.getAllMonkeyNftFor(user);

        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);
        assertEq(monkeyNft.balanceOf(user), 1);
        assertEq(monkeyNft.s_tokenCounter(), 2);
        assert(traits.monkeyType == MonkeyNft.MonkeyType.FARMER);
    }

    function testFarmMonkey() external {
        address user = makeAddr("user");
        uint256 tokenId = _mintMonkey(user, MonkeyNft.MonkeyType.FARMER);
        
        vm.startPrank(user);
        monkeyNft.approve(address(bananaToken), tokenId);
        bananaToken.stakeMonkey(tokenId);
        vm.stopPrank();
        BananaToken.StakingStats memory stats = bananaToken.getMonkeyStakingStats(tokenId);
        assertEq(stats.owner, user);
        assertEq(stats.stakeTime, block.timestamp);

        assertEq(bananaToken.balanceOf(user), 0);
        assertEq(monkeyNft.balanceOf(user), 0);
        assertEq(monkeyNft.balanceOf(address(bananaToken)), 1);
        assertEq(monkeyNft.ownerOf(tokenId), address(bananaToken));

        // fast forward 2 days
        vm.warp(block.timestamp + 2 days);
        vm.prank(user);
        bananaToken.collectFarmedBananas(tokenId);
        stats = bananaToken.getMonkeyStakingStats(tokenId);
        assertEq(stats.bananaFarmed, 200e18);
        assertEq(bananaToken.balanceOf(user), 200e18);

        vm.prank(user);
        bananaToken.unstakeMonkey(tokenId);
        assertEq(monkeyNft.balanceOf(user), 1);
        assertEq(monkeyNft.ownerOf(tokenId), user);
    }

    function testGuardFarmerMoneky() external {
        address user = makeAddr("user");
        uint256 farmerTokenId = _mintMonkey(user, MonkeyNft.MonkeyType.FARMER);

        address guardUser = makeAddr("guardUser");
        uint256 guardianTokenId = _mintMonkey(guardUser, MonkeyNft.MonkeyType.GUARDIAN);

        vm.prank(guardUser);
        monkeyNft.guardMonkey(guardianTokenId, farmerTokenId);

        MonkeyNft.MonkeyTraits memory farmerTraits = monkeyNft.getMonkeyInfo(farmerTokenId);
        assert(farmerTraits.isGuarded);
    }

    function _mintMonkey(address user, MonkeyNft.MonkeyType monkeyType) internal returns (uint256 tokenId) {
        uint256 randomWord;
        if (monkeyType == MonkeyNft.MonkeyType.FARMER) {
            randomWord = 778;
        } else if (monkeyType == MonkeyNft.MonkeyType.CHAOTIC) {
            randomWord = 777;
        } else if (monkeyType == MonkeyNft.MonkeyType.GUARDIAN) {
            randomWord = 776;
        }

        vm.prank(user);
        uint256 requestId = monkeyNft.requestMintMonkeyNft();

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomWord; 
        tokenId = monkeyNft.s_tokenCounter();
        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(monkeyNft), randomWords);

        MonkeyNft.MonkeyTraits memory traits = monkeyNft.getMonkeyInfo(tokenId);
        assert(traits.monkeyType == monkeyType);
    }
}
