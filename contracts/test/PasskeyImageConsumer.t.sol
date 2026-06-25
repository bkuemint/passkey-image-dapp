// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PasskeyImageConsumer.sol";

contract PasskeyImageConsumerTest is Test {
    PasskeyImageConsumer public consumer;
    address constant ASYNC_DELIVERY = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address constant SECP256R1 = address(0x100);

    event KeyRegistered(address indexed user, bytes32 x, bytes32 y);

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
}
