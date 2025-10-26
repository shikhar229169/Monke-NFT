// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { MonkeyNft } from "src/MonkeyNft.sol";
import { BananaToken } from "src/BananaToken.sol";

contract MonkeyNftDeploy is Script {
    function run() external returns (MonkeyNft, BananaToken) {
        address linkToken = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;
        address vrfCoordinator = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
        bytes32 keyHash = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
        uint256 subId = 88446659494151829970515044852417146112917445623344163627676607786378688929921;

        MonkeyNft.VrfConfig memory vrfConfig = MonkeyNft.VrfConfig({
            keyHash: keyHash,
            subId: uint64(subId),
            requestConfirmations: 3,
            callbackGasLimit: 500000,
            numWords: 1,
            enableNativePayment: true
        });

        vm.startBroadcast();
        
        MonkeyNft monkeyNft = new MonkeyNft(vrfCoordinator, vrfConfig, linkToken);
        BananaToken bananaToken = new BananaToken(address(monkeyNft));
        monkeyNft.setBananaTokenAddress(address(bananaToken));

        vm.stopBroadcast();

        return (monkeyNft, bananaToken);
    }
}