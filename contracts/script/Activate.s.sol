// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PasskeyImageConsumer.sol";

contract ActivateScript is Script {
    address constant CONSUMER        = 0x3f80d4908C1ABfeb34E8851d35Af9e1e95B2dB20;
    address constant EXECUTOR        = 0x833c7a5c0628b3d47D12c3556AC1B02B2723f390;
    bytes constant EXECUTOR_PUB_KEY  = hex"043211c1a7ceaf5799b67469ff4aedf5784235b2c869782bb31bf1dc44d3ec1e1ead6e65c1e2d1c16121c12eac1631d707450f0ba72f353ae297c0426a8a95aeb4";
    PasskeyImageConsumer private constant consumer = PasskeyImageConsumer(payable(CONSUMER));

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Using hardcoded executor (bypassed TEEServiceRegistry due to RPC pruning)
        address executor = EXECUTOR;
        console.log("Using executor:", executor);

        // Read pre-encrypted secrets from file (generated offline via prepare-secret.cjs)
        // This avoids vm.ffi issues on Windows (process-spawning hangs)
        string memory encryptedHex = vm.readFile("script/encrypted-secret.hex");
        bytes memory encryptedSecrets = vm.parseBytes(encryptedHex);
        console.log("Encrypted secrets ready. Length:", encryptedSecrets.length);

        // Build SovereignAgentParams for a ZeroClaw monitoring agent
        string[] memory tools = new string[](0);
        PasskeyImageConsumer.SovereignStorageRef[] memory emptySkills = new PasskeyImageConsumer.SovereignStorageRef[](0);
        PasskeyImageConsumer.SovereignStorageRef memory emptyRef = PasskeyImageConsumer.SovereignStorageRef("", "", "");

        PasskeyImageConsumer.SovereignAgentParams memory params = PasskeyImageConsumer.SovereignAgentParams({
            executor: executor,
            ttl: 500,
            userPublicKey: bytes(""),
            pollIntervalBlocks: 5,
            maxPollBlock: 6000,
            taskIdMarker: "passkey-monitor",
            deliveryTarget: CONSUMER,
            deliverySelector: consumer.onSovereignAgentResult.selector,
            deliveryGasLimit: 500_000,
            deliveryMaxFeePerGas: 1e9,
            deliveryMaxPriorityFeePerGas: 1e8,
            agentType: 6,
            prompt: "You are a monitoring agent for PasskeyImageConsumer, a dApp on Ritual Chain that generates AI images. "
                    "Each time you wake up, check the contract state and prepare a brief status report. "
                    "Report the total image request count and any recent activity. "
                    "Keep responses concise (under 200 tokens).",
            encryptedSecrets: encryptedSecrets,
            convoHistory: emptyRef,
            output: emptyRef,
            skills: emptySkills,
            systemPrompt: emptyRef,
            model: "zai-org/GLM-4.7-FP8",
            tools: tools,
            maxTurns: 3,
            maxTokens: 1024,
            rpcUrls: '{"ritual":"https://rpc.ritualfoundation.org"}'
        });

        // ~11.7 min between calls (2000 blocks x 350ms ~ 11.7 min)
        // windowNumCalls = 5 gives ~58 min per window; rolling window auto-extends
        PasskeyImageConsumer.SovereignScheduleConfig memory schedule = PasskeyImageConsumer.SovereignScheduleConfig({
            schedulerGas: 500_000,
            frequency: 2000,
            schedulerTtl: 500,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            value: 0
        });

        // MAX_LIFESPAN = 10,000 blocks; frequency=2000 → windowNumCalls must be ≤5
        PasskeyImageConsumer.SovereignRollingConfig memory rolling = PasskeyImageConsumer.SovereignRollingConfig({
            windowNumCalls: 5,
            rolloverThresholdBps: 5000,
            rolloverRetryEveryCalls: 1
        });

        vm.startBroadcast(deployerPrivateKey);

        uint256 callId = consumer.configureFundAndStart{value: 0.05 ether}(
            params, schedule, rolling, 100_000
        );

        vm.stopBroadcast();

        console.log("Sovereign agent activated at:", CONSUMER);
        console.log("Scheduler call ID:", callId);
        console.log("Frequency: ~11.7 min (2000 blocks)");
        console.log("Window size:", uint256(5));
    }


}
