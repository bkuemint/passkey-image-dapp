// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PasskeyImageConsumer.sol";

contract PasskeyImageConsumerTest is Test {
    PasskeyImageConsumer public consumer;
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address constant SECP256R1 = address(0x100);

    event KeyRegistered(address indexed user, bytes32 x, bytes32 y);
    event SovereignConfigured(address indexed owner);
    event SovereignStarted(uint256 indexed callId, uint32 numCalls, uint32 frequency);
    event SovereignStopped();
    event SovereignInvoked(uint256 indexed executionIndex, uint64 indexed seriesId, bytes output);
    event SovereignResult(bytes32 indexed jobId, bytes result);
    event SovereignRestarted(uint256 indexed callId);

    function setUp() public {
        consumer = new PasskeyImageConsumer();
    }

    function test_ownerSet() public {
        assertEq(consumer.owner(), address(this));
    }

    function test_registerKey() public {
        bytes32 x = bytes32(uint256(1));
        bytes32 y = bytes32(uint256(2));

        vm.expectEmit(true, true, true, true);
        emit KeyRegistered(address(this), x, y);
        consumer.registerKey(x, y);

        (bytes32 storedX, bytes32 storedY) = consumer.getRegisteredKey(address(this));
        assertEq(storedX, x);
        assertEq(storedY, y);
    }

    function test_callbackOnlyFromDelivery() public {
        bytes32 jobId = keccak256("test");
        bytes memory result = abi.encode(
            false, bytes(""), "https://storage.googleapis.com/bucket/img.png",
            bytes32(0), false, uint32(0), uint32(0), uint32(0), ""
        );

        vm.prank(address(0xdead));
        vm.expectRevert("Only AsyncDelivery");
        consumer.onImageReady(jobId, result);

        vm.prank(ASYNC_DELIVERY);
        consumer.onImageReady(jobId, result);

        PasskeyImageConsumer.ImageRequest memory req = consumer.getRequest(jobId);
        assertTrue(req.fulfilled);
    }

    function test_callbackIdempotent() public {
        bytes32 jobId = keccak256("test2");
        bytes memory result = abi.encode(
            false, bytes(""), "https://storage.googleapis.com/bucket/img.png",
            bytes32(0), false, uint32(0), uint32(0), uint32(0), ""
        );

        vm.prank(ASYNC_DELIVERY);
        consumer.onImageReady(jobId, result);

        vm.prank(ASYNC_DELIVERY);
        vm.expectRevert("Already fulfilled");
        consumer.onImageReady(jobId, result);
    }

    function test_callbackError() public {
        bytes32 jobId = keccak256("test3");
        bytes memory result = abi.encode(
            true, bytes(""), "", bytes32(0), false,
            uint32(0), uint32(0), uint32(0), "Generation failed"
        );

        vm.prank(ASYNC_DELIVERY);
        consumer.onImageReady(jobId, result);

        PasskeyImageConsumer.ImageRequest memory req = consumer.getRequest(jobId);
        assertTrue(req.fulfilled);
        assertTrue(req.failed);
        assertEq(req.errorMessage, "Generation failed");
    }

    function test_depositFees() public {
        vm.etch(
            address(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948),
            hex"60006000f3"  // RETURN(0,0) — mock contract accepts any call
        );
        vm.deal(address(this), 1 ether);
        consumer.depositFees{value: 0.5 ether}(100_000);
        assertTrue(address(consumer).balance == 0);
    }

    function test_authenticateNotRegistered() public {
        vm.expectRevert("Key not registered");
        consumer.authenticate(address(0x1234), hex"00", hex"00");
    }

    /* ─────────────── Scheduler / Auto-Generation Tests ─────────────── */

    address constant SCHEDULER = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;

    function test_scheduleAutomaticImage_revertsNonOwner() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Not owner");
        consumer.scheduleAutomaticImage("test", 300_000, 1 gwei, 730);
    }

    function test_scheduleAutomaticImage_setsState() public {
        vm.mockCall(
            SCHEDULER,
            abi.encodeWithSelector(IScheduler.schedule.selector),
            abi.encode(uint256(42))
        );

        consumer.scheduleAutomaticImage("Daily Ritual image", 300_000, 1 gwei, 730);

        assertEq(consumer.activeScheduleId(), 42);
        assertEq(consumer.scheduleBasePrompt(), "Daily Ritual image");
        assertEq(consumer.scheduledImageCount(), 0);
    }

    function test_scheduleAutomaticImage_revertsIfAlreadyActive() public {
        vm.mockCall(
            SCHEDULER,
            abi.encodeWithSelector(IScheduler.schedule.selector),
            abi.encode(uint256(1))
        );

        consumer.scheduleAutomaticImage("test", 300_000, 1 gwei, 730);

        vm.expectRevert("Already scheduled");
        consumer.scheduleAutomaticImage("test2", 300_000, 1 gwei, 730);
    }

    function test_executeScheduledImage_revertsNonScheduler() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Only scheduler");
        consumer.executeScheduledImage(0);
    }

    function test_cancelAutomaticSchedule_revertsNonOwner() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Not owner");
        consumer.cancelAutomaticSchedule();
    }

    function test_cancelAutomaticSchedule_revertsIfNoneActive() public {
        vm.expectRevert("No active schedule");
        consumer.cancelAutomaticSchedule();
    }

    function test_shouldExecute_initiallyTrue() public {
        assertTrue(consumer.shouldExecute(address(0), 0, 0));
    }

    function test_shouldExecute_blocksAfterExecution() public {
        vm.mockCall(
            SCHEDULER,
            abi.encodeWithSelector(IScheduler.schedule.selector),
            abi.encode(uint256(1))
        );

        consumer.scheduleAutomaticImage("test", 300_000, 1 gwei, 730);
        assertTrue(consumer.shouldExecute(address(0), 0, 0));

        vm.mockCall(
            0x0000000000000000000000000000000000000818,
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.prank(SCHEDULER);
        consumer.executeScheduledImage(0);

        assertFalse(consumer.shouldExecute(address(0), 0, 0));

        vm.warp(block.timestamp + 43200);
        assertTrue(consumer.shouldExecute(address(0), 0, 0));
    }

    function test_executeScheduledImage_incrementsCount() public {
        vm.mockCall(
            SCHEDULER,
            abi.encodeWithSelector(IScheduler.schedule.selector),
            abi.encode(uint256(1))
        );

        consumer.scheduleAutomaticImage("Auto image", 300_000, 1 gwei, 730);

        vm.mockCall(
            0x0000000000000000000000000000000000000818,
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.prank(SCHEDULER);
        consumer.executeScheduledImage(0);

        assertEq(consumer.scheduledImageCount(), 1);
        assertEq(consumer.getRequestCount(), 1);
        assertTrue(consumer.lastScheduledExecution() > 0);
    }

    function test_setScheduleBasePrompt_onlyOwner() public {
        consumer.setScheduleBasePrompt("new prompt");
        assertEq(consumer.scheduleBasePrompt(), "new prompt");

        vm.prank(address(0xdead));
        vm.expectRevert("Not owner");
        consumer.setScheduleBasePrompt("not allowed");
    }

    // ═══════════════════════════════════════════════════════════════
    //  Sovereign Agent (0x080C) Lifecycle Tests
    // ═══════════════════════════════════════════════════════════════

    function _defaultStorageRef() internal pure returns (PasskeyImageConsumer.SovereignStorageRef memory) {
        return PasskeyImageConsumer.SovereignStorageRef("", "", "");
    }

    function _defaultParams() internal pure returns (PasskeyImageConsumer.SovereignAgentParams memory) {
        string[] memory emptyTools = new string[](0);
        PasskeyImageConsumer.SovereignStorageRef[] memory emptySkills = new PasskeyImageConsumer.SovereignStorageRef[](0);
        return PasskeyImageConsumer.SovereignAgentParams({
            executor: address(0),
            ttl: 300,
            userPublicKey: bytes(""),
            pollIntervalBlocks: 5,
            maxPollBlock: 6000,
            taskIdMarker: "",
            deliveryTarget: address(0),
            deliverySelector: bytes4(0),
            deliveryGasLimit: 500_000,
            deliveryMaxFeePerGas: 1e9,
            deliveryMaxPriorityFeePerGas: 1e8,
            agentType: 6,
            prompt: "Generate an image",
            encryptedSecrets: bytes(""),
            convoHistory: _defaultStorageRef(),
            output: _defaultStorageRef(),
            skills: emptySkills,
            systemPrompt: _defaultStorageRef(),
            model: "flux-schnell",
            tools: emptyTools,
            maxTurns: 50,
            maxTokens: 8192,
            rpcUrls: ""
        });
    }

    function _defaultSchedule() internal pure returns (PasskeyImageConsumer.SovereignScheduleConfig memory) {
        return PasskeyImageConsumer.SovereignScheduleConfig({
            schedulerGas: 300_000,
            frequency: 2000,
            schedulerTtl: 500,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e8,
            value: 0
        });
    }

    function _defaultRolling() internal pure returns (PasskeyImageConsumer.SovereignRollingConfig memory) {
        return PasskeyImageConsumer.SovereignRollingConfig({
            windowNumCalls: 5,
            rolloverThresholdBps: 5000,
            rolloverRetryEveryCalls: 1
        });
    }

    function _mockScheduler() internal {
        vm.mockCall(
            SCHEDULER,
            abi.encodeWithSelector(IScheduler.schedule.selector),
            abi.encode(uint256(42))
        );
        vm.mockCall(
            SCHEDULER,
            abi.encodeWithSelector(IScheduler.cancel.selector),
            abi.encode()
        );
    }

    // ── Initial State ───────────────────────────────────────────────

    function test_initialSovereignState() public view {
        assertFalse(consumer.configured());
        assertEq(uint8(consumer.wakeMode()), uint8(SovereignWakeMode.NONE));
        assertEq(uint8(consumer.executorMode()), uint8(SovereignExecutorMode.PINNED));
        assertEq(consumer.activeCallId(), 0);
        assertEq(consumer.activeNumCalls(), 0);
        assertEq(consumer.currentSeriesId(), 0);
        assertEq(consumer.pendingSeriesId(), 0);
        assertEq(consumer.pendingCallId(), 0);
        assertEq(consumer.thresholdIndex(), 0);
        assertFalse(consumer.hasStartConfig());
    }

    // ── configureFundAndStart ───────────────────────────────────────

    function test_configureFundAndStart_setsState() public {
        _mockScheduler();
        PasskeyImageConsumer.SovereignAgentParams memory p = _defaultParams();
        PasskeyImageConsumer.SovereignScheduleConfig memory s = _defaultSchedule();
        PasskeyImageConsumer.SovereignRollingConfig memory r = _defaultRolling();

        vm.expectEmit(true, true, true, true);
        emit SovereignConfigured(address(this));
        vm.expectEmit(true, true, true, true);
        emit SovereignStarted(42, r.windowNumCalls, s.frequency);

        consumer.configureFundAndStart(p, s, r, 5000);

        assertTrue(consumer.configured());
        assertEq(uint8(consumer.wakeMode()), uint8(SovereignWakeMode.ROLLING_FIXED_WINDOW));
        assertEq(consumer.activeCallId(), 42);
        assertEq(consumer.activeNumCalls(), r.windowNumCalls);
        assertTrue(consumer.hasStartConfig());
    }

    function test_configureFundAndStart_revertsNonOwner() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Not owner");
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);
    }

    function test_configureFundAndStart_revertsAlreadyRunning() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);

        vm.expectRevert();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);
    }

    function test_configureFundAndStart_depositsToWallet() public {
        address wallet = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
        vm.etch(wallet, hex"60006000f3");
        _mockScheduler();
        vm.deal(address(this), 10 ether);

        vm.expectCall(
            wallet,
            abi.encodeWithSelector(IRitualWallet.depositFor.selector, address(consumer), 5000)
        );
        consumer.configureFundAndStart{value: 5 ether}(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);
    }

    // ── stop ────────────────────────────────────────────────────────

    function test_stop_setsWakeModeNone() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);

        vm.expectEmit(true, true, true, true);
        emit SovereignStopped();
        consumer.stop();

        assertEq(uint8(consumer.wakeMode()), uint8(SovereignWakeMode.NONE));
        assertEq(consumer.activeCallId(), 0);
    }

    function test_stop_revertsNonOwner() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);

        vm.prank(address(0xdead));
        vm.expectRevert("Not owner");
        consumer.stop();
    }

    function test_stop_idempotent() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);
        consumer.stop();
        consumer.stop();
        assertEq(uint8(consumer.wakeMode()), uint8(SovereignWakeMode.NONE));
    }

    // ── restart ─────────────────────────────────────────────────────

    function test_restart_revertsNotConfigured() public {
        vm.expectRevert();
        consumer.restart();
    }

    function test_restart_revertsNonOwner() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);

        vm.prank(address(0xdead));
        vm.expectRevert("Not owner");
        consumer.restart();
    }

    function test_restart_afterStop() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);
        consumer.stop();

        vm.expectEmit(true, true, true, true);
        emit SovereignRestarted(42);
        consumer.restart();

        assertEq(uint8(consumer.wakeMode()), uint8(SovereignWakeMode.ROLLING_FIXED_WINDOW));
        assertEq(consumer.activeCallId(), 42);
    }

    function test_restart_fromConfigured() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);

        vm.expectEmit(true, true, true, true);
        emit SovereignRestarted(42);
        consumer.restart();

        assertEq(uint8(consumer.wakeMode()), uint8(SovereignWakeMode.ROLLING_FIXED_WINDOW));
        assertEq(consumer.activeCallId(), 42);
    }

    // ── wakeUp ──────────────────────────────────────────────────────

    function test_wakeUp_revertsNonScheduler() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Only scheduler");
        consumer.wakeUp(0, 0);
    }

    function test_wakeUp_withNoneMode() public {
        vm.prank(SCHEDULER);
        consumer.wakeUp(0, 0);
    }

    function test_wakeUp_invokesPrecompile() public {
        _mockScheduler();
        consumer.configureFundAndStart(_defaultParams(), _defaultSchedule(), _defaultRolling(), 5000);

        vm.mockCall(
            address(0x080C),
            bytes(""),
            abi.encode(bytes(""))
        );
        vm.prank(SCHEDULER);
        consumer.wakeUp(0, 0);
    }

    // ── onSovereignAgentResult ──────────────────────────────────────

    function test_onSovereignAgentResult_revertsNonDelivery() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Only AsyncDelivery");
        consumer.onSovereignAgentResult(keccak256("test"), bytes(""));
    }

    function test_onSovereignAgentResult_emitsEvent() public {
        bytes32 jobId = keccak256("test-job");
        bytes memory result = bytes("some result data");

        vm.expectEmit(true, true, true, true);
        emit SovereignResult(jobId, result);
        vm.prank(ASYNC_DELIVERY);
        consumer.onSovereignAgentResult(jobId, result);
    }

    // ── scheduleConfig / rollingConfig ──────────────────────────────

    function test_scheduleConfigStored() public {
        _mockScheduler();
        PasskeyImageConsumer.SovereignScheduleConfig memory s = _defaultSchedule();
        consumer.configureFundAndStart(_defaultParams(), s, _defaultRolling(), 5000);

        (uint32 storedGas, uint32 storedFreq, uint32 storedTtl, uint256 storedMaxFee, uint256 storedMaxPri, uint256 storedVal) = consumer.scheduleConfig();
        assertEq(storedGas, s.schedulerGas);
        assertEq(storedFreq, s.frequency);
        assertEq(storedTtl, s.schedulerTtl);
    }
}
