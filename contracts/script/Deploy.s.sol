// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PasskeyImageConsumer.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PasskeyImageConsumer consumer = new PasskeyImageConsumer();
        console.log("PasskeyImageConsumer deployed at:", address(consumer));

        vm.stopBroadcast();
    }
}
