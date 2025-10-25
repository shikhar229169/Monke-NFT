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

    // enums
    enum MonkeyType {
        CHAOTIC,
        FARMER,
        GUARD,
        REGULAR
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
    }

    struct VrfConfig {
        bytes32 keyHash;
        uint64 subId;
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
    uint256 public s_tokenCounter;
    VrfConfig public s_vrfConfig;
    mapping(uint256 tokenId => MonkeyTraits) private s_monkeyInfo;
    mapping(address owner => uint256[] tokenIds) public s_monkeyOwnerToTokenIds;
    mapping(uint256 requestId => address owner) public s_mintRequests;

    modifier onlyMonke {
        if (msg.sender != MONKE) {
            revert MonkeyNft__ONLY_MONKE();
        } 
        _;
    }

    constructor(address _vrfCoordinator, VrfConfig memory _vrfConfig) ERC721("MonkeyNft", "MNFT") VRFConsumerBaseV2Plus(_vrfCoordinator) {
        MONKE = msg.sender;
        s_vrfConfig = _vrfConfig;
        s_tokenCounter = 1;
    }

    function setBananaTokenAddress(address _bananaToken) external onlyMonke {
        bananaToken = _bananaToken;
    }

    function updateConfig(VrfConfig memory _vrfConfig) external onlyMonke {
        s_vrfConfig = _vrfConfig;
    }

    function requestMintMonkeyNft() external returns (uint256 requestId) {
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
        s_mintRequests[requestId] = msg.sender;
        emit MonkeyMintRequested(requestId, msg.sender, block.timestamp);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_mintRequests[_requestId] != address(0), MonkeyNft__InvalidRequestId());
        address monkeyOwner = s_mintRequests[_requestId];
        _safeMint(monkeyOwner, s_tokenCounter);
        uint256 randomWord = _randomWords[0];
        uint256 tokenId = s_tokenCounter++;

        uint256 monkeyType = randomWord % 4;
        uint256 rarity = (randomWord >> 8) % 4;
        uint256 farmingPower = ((randomWord >> 16) % 100) + 1;

        s_monkeyInfo[tokenId] = MonkeyTraits({
            owner: monkeyOwner,
            monkeyType: MonkeyType(monkeyType),
            rarity: Rarity(rarity),
            farmingPower: farmingPower,
            creationTimestamp: block.timestamp
        });

        s_monkeyOwnerToTokenIds[monkeyOwner].push(tokenId);
        emit MonkeyMinted(monkeyOwner, tokenId);
    }

    function _update(address _to, uint256 _tokenId, address _auth) internal override returns (address) {
        require(_auth == address(0) || _to == bananaToken || _auth == bananaToken, MonkeyNft__UnauthorizedTransfer());
        return super._update(_to, _tokenId, _auth);
    }

    function getMonkeyInfo(uint256 _tokenId) external view returns (MonkeyTraits memory) {
        return s_monkeyInfo[_tokenId];
    }
}
