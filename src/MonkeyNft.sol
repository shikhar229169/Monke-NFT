// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract MonkeyNft is ERC721, VRFConsumerBaseV2Plus {
    // errors
    error MonkeyNft__ONLY_MONKE();
    error MonkeyNft__InvalidRequestId();
    error MonkeyNft__UnauthorizedTransfer();
    error MonkeyNft__AlreadyGuarded();
    error MonkeyNft__AttackOnCooldown();

    // enums
    enum MonkeyType {
        CHAOTIC,
        FARMER,
        GUARDIAN
    }

    enum Rarity {
        COMMON,
        RARE,
        EPIC,
        LEGENDARY
    }

    // structs
    struct MonkeyTraits {
        address owner;
        MonkeyType monkeyType;
        Rarity rarity;
        uint256 farmingPower;
        uint256 creationTimestamp;
        bool isGuarded;
        uint256 attackCooldown;
    }

    struct VrfConfig {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bool enableNativePayment;
    }

    // Events
    event MonkeyMintRequested(uint256 requestId, address owner, uint256 requestTime);
    event MonkeyMinted(address owner, uint256 tokenId);

    address public MONKE;
    address public bananaToken;
    address public linkToken;
    uint256 public s_tokenCounter;
    VrfConfig public s_vrfConfig;
    mapping(uint256 tokenId => MonkeyTraits) private s_monkeyInfo;
    mapping(address owner => uint256[] tokenIds) public s_monkeyOwnerToTokenIds;
    mapping(uint256 requestId => address owner) public s_mintRequests;
    mapping(uint256 requestId => uint256 attackerTokenId) public s_attackRequests;
    mapping(uint256 guardTokenId => uint256 tokenId) public s_guardedMonkeys;

    modifier onlyMonke {
        if (msg.sender != MONKE) {
            revert MonkeyNft__ONLY_MONKE();
        } 
        _;
    }

    constructor(address _vrfCoordinator, VrfConfig memory _vrfConfig, address _linkToken) ERC721("MonkeyNft", "MNFT") VRFConsumerBaseV2Plus(_vrfCoordinator) {
        MONKE = msg.sender;
        s_vrfConfig = _vrfConfig;
        s_tokenCounter = 1;
        linkToken = _linkToken;
    }

    function setBananaTokenAddress(address _bananaToken) external onlyMonke {
        bananaToken = _bananaToken;
    }

    function updateConfig(VrfConfig memory _vrfConfig) external onlyMonke {
        s_vrfConfig = _vrfConfig;
    }

    function requestMintMonkeyNft() external returns (uint256 requestId) {
        require(s_monkeyOwnerToTokenIds[msg.sender].length == 0);

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_vrfConfig.keyHash,
                subId: s_vrfConfig.subId,
                requestConfirmations: s_vrfConfig.requestConfirmations,
                callbackGasLimit: s_vrfConfig.callbackGasLimit,
                numWords: s_vrfConfig.numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: s_vrfConfig.enableNativePayment}))
            })
        );
        s_mintRequests[requestId] = msg.sender;
        emit MonkeyMintRequested(requestId, msg.sender, block.timestamp);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_mintRequests[_requestId] != address(0), MonkeyNft__InvalidRequestId());

        if (s_mintRequests[_requestId] != address(0)) {
            _mintMonkeyNft(_requestId, _randomWords);
        }
        else if (s_attackRequests[_requestId] != 0) {
            _attackMonkeyFulfillRequest(_requestId, _randomWords);
        }
        else {
            revert MonkeyNft__InvalidRequestId();
        }
    }

    function _mintMonkeyNft(uint256 _requestId, uint256[] calldata _randomWords) internal {
        require(s_monkeyOwnerToTokenIds[msg.sender].length == 0);
        address monkeyOwner = s_mintRequests[_requestId];
        s_mintRequests[_requestId] = address(0);
        _safeMint(monkeyOwner, s_tokenCounter);
        uint256 randomWord = _randomWords[0];
        uint256 tokenId = s_tokenCounter++;

        uint256 monkeyType = randomWord % 3;
        uint256 rarity = (randomWord >> 8) % 4;
        uint256 farmingPower = ((randomWord >> 16) % 100) + 1;

        s_monkeyInfo[tokenId] = MonkeyTraits({
            owner: monkeyOwner,
            monkeyType: MonkeyType(monkeyType),
            rarity: Rarity(rarity),
            farmingPower: farmingPower,
            creationTimestamp: block.timestamp,
            isGuarded: false,
            attackCooldown: 0
        });

        s_monkeyOwnerToTokenIds[monkeyOwner].push(tokenId);
        emit MonkeyMinted(monkeyOwner, tokenId);
    }

    function guardMonkey(uint256 guardTokenId, uint256 tokenId) external {
        require(s_guardedMonkeys[guardTokenId] == 0, MonkeyNft__AlreadyGuarded());
        MonkeyTraits memory guardMonkeyInfo = s_monkeyInfo[guardTokenId];
        require(guardMonkeyInfo.monkeyType == MonkeyType.GUARDIAN && guardMonkeyInfo.owner == msg.sender, MonkeyNft__ONLY_MONKE());
        
        MonkeyTraits memory targetMonkey = s_monkeyInfo[tokenId];
        require(!targetMonkey.isGuarded && targetMonkey.monkeyType == MonkeyType.FARMER, MonkeyNft__AlreadyGuarded());
        s_monkeyInfo[tokenId].isGuarded = true;
    }

    function attackMonkey(uint256 attackerTokenId) external returns (uint256 requestId) {
        MonkeyTraits memory attackerMonkeyInfo = s_monkeyInfo[attackerTokenId];
        require(attackerMonkeyInfo.monkeyType == MonkeyType.CHAOTIC && attackerMonkeyInfo.owner == msg.sender, MonkeyNft__ONLY_MONKE());
        require(attackerMonkeyInfo.attackCooldown <= block.timestamp, MonkeyNft__AttackOnCooldown());

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_vrfConfig.keyHash,
                subId: s_vrfConfig.subId,
                requestConfirmations: s_vrfConfig.requestConfirmations,
                callbackGasLimit: s_vrfConfig.callbackGasLimit,
                numWords: s_vrfConfig.numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );

        s_attackRequests[requestId] = attackerTokenId;
        s_monkeyInfo[attackerTokenId].attackCooldown = type(uint256).max;
        emit MonkeyMintRequested(requestId, msg.sender, block.timestamp);
    }

    function _attackMonkeyFulfillRequest(uint256 _requestId, uint256[] calldata _randomWords) internal {
        uint256 attackerTokenId = s_attackRequests[_requestId];
        s_attackRequests[_requestId] = 0;

        uint256 randomWord = _randomWords[0];
        uint256 targetTokenId = (randomWord % (s_tokenCounter - 1)) + 1;

        MonkeyTraits memory targetMonkey = s_monkeyInfo[targetTokenId];
        if (targetMonkey.isGuarded) {
            s_monkeyInfo[targetTokenId].isGuarded = false;
            s_monkeyInfo[attackerTokenId].attackCooldown = block.timestamp + 2 days;
        } else {
            s_monkeyInfo[attackerTokenId].attackCooldown = block.timestamp + 1 days;
            uint256 reduceFarmingPowerBy = randomWord % 10;
            if (s_monkeyInfo[targetTokenId].farmingPower > reduceFarmingPowerBy) {
                s_monkeyInfo[targetTokenId].farmingPower -= reduceFarmingPowerBy;
            }
        }
    }

    function _update(address _to, uint256 _tokenId, address _auth) internal override returns (address) {
        require(_auth == address(0) || _to == bananaToken || _auth == bananaToken, MonkeyNft__UnauthorizedTransfer());
        return super._update(_to, _tokenId, _auth);
    }

    function getMonkeyInfo(uint256 _tokenId) external view returns (MonkeyTraits memory) {
        return s_monkeyInfo[_tokenId];
    }

    function getVrfConfig() external view returns (VrfConfig memory) {
        return s_vrfConfig;
    }

    function getAllMonkeyNftFor(address owner) external view returns (uint256[] memory) {
        return s_monkeyOwnerToTokenIds[owner];
    }
}
