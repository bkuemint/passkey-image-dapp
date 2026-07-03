// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address to, uint256 lockDuration) external payable;
    function balanceOf(address user) external view returns (uint256);
}

interface IScheduler {
    function schedule(
        bytes calldata data,
        uint32 gas,
        uint32 startBlock,
        uint32 numCalls,
        uint32 frequency,
        uint32 ttl,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint256 value,
        address payer,
        address predicate
    ) external returns (uint256 callId);

    function cancel(uint256 callId) external;
}

enum SovereignWakeMode { NONE, ROLLING_FIXED_WINDOW }
enum SovereignExecutorMode { PINNED, RESOLVE_AT_INVOCATION }

contract PasskeyImageConsumer {
    address constant IMAGE_PRECOMPILE = 0x0000000000000000000000000000000000000818;
    address constant RITUAL_WALLET    = 0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948;
    address constant ASYNC_DELIVERY   = 0x5A16214fF555848411544b005f7Ac063742f39F6;
    address constant SECP256R1        = 0x0000000000000000000000000000000000000100;
    address constant SCHEDULER        = 0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B;
    address constant SOVEREIGN_AGENT_PRECOMPILE = 0x000000000000000000000000000000000000080C;
    address constant TEE_REGISTRY                = 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F;

    struct P256Key {
        bytes32 x;
        bytes32 y;
    }

    struct ImageRequest {
        address user;
        string prompt;
        string uri;
        bytes32 contentHash;
        bool fulfilled;
        bool failed;
        string errorMessage;
    }

    address public owner;
    mapping(address => P256Key) private _registeredKeys;
    mapping(bytes32 => ImageRequest) private _requests;
    bytes32[] public requestIds;

    uint256 public activeScheduleId;
    uint256 public scheduledImageCount;
    uint256 public lastScheduledExecution;
    string public scheduleBasePrompt;
    StorageRef public scheduleOutputRef;

    bool public configured;
    SovereignWakeMode public wakeMode;
    SovereignExecutorMode public executorMode;
    uint256 public activeCallId;
    uint32 public activeNumCalls;
    uint64 public currentSeriesId;
    uint64 public pendingSeriesId;
    uint64 public nextSeriesId;
    uint256 public pendingCallId;
    uint32 public thresholdIndex;
    bool public hasStartConfig;
    SovereignAgentParams internal params;
    bytes internal sovereignInputTemplate;
    SovereignScheduleConfig public scheduleConfig;
    SovereignRollingConfig public rollingConfig;
    uint256 private _launchStatus;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    error AlreadyRunning();
    error NotConfigured();
    error SovereignCallFailed();
    error NoValidExecutor();
    error InvalidWakeMode();

    event KeyRegistered(address indexed user, bytes32 x, bytes32 y);
    event ImageRequested(bytes32 indexed jobId, address indexed user, string prompt);
    event ImageReady(bytes32 indexed jobId, address indexed user, string uri);
    event ImageFailed(bytes32 indexed jobId, string error);
    event AutoScheduleSet(uint256 indexed callId, uint256 frequency, uint256 numCalls, string basePrompt);
    event AutoScheduleCancelled(uint256 indexed callId);
    event ScheduledImageCreated(uint256 indexed executionIndex, bytes32 indexed jobId, string prompt);
    event SovereignConfigured(address indexed owner);
    event SovereignStarted(uint256 indexed callId, uint32 numCalls, uint32 frequency);
    event SovereignStopped();
    event SovereignInvoked(uint256 indexed executionIndex, uint64 indexed seriesId, bytes output);
    event SovereignResult(bytes32 indexed jobId, bytes result);
    event SovereignRestarted(uint256 indexed callId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAsyncDelivery() {
        require(msg.sender == ASYNC_DELIVERY, "Only AsyncDelivery");
        _;
    }

    modifier onlyScheduler() {
        require(msg.sender == SCHEDULER, "Only scheduler");
        _;
    }

    constructor() {
        owner = msg.sender;
        scheduleOutputRef = StorageRef("hf", "", "");
    }

    receive() external payable {}

    function shouldExecute(address, uint256, uint256) external view returns (bool) {
        return lastScheduledExecution == 0 || block.timestamp >= lastScheduledExecution + 43200;
    }

    function depositFees(uint256 lockDuration) external payable onlyOwner {
        IRitualWallet(RITUAL_WALLET).deposit{value: msg.value}(lockDuration);
    }

    function registerKey(bytes32 x, bytes32 y) external {
        _registeredKeys[msg.sender] = P256Key(x, y);
        emit KeyRegistered(msg.sender, x, y);
    }

    function authenticate(
        address user,
        bytes calldata message,
        bytes calldata signature
    ) external view returns (bool) {
        P256Key memory key = _registeredKeys[user];
        require(key.x != bytes32(0), "Key not registered");

        bytes memory pubkey = abi.encodePacked(bytes1(0x04), key.x, key.y);
        bytes memory input = abi.encode(pubkey, message, signature);

        (bool success, bytes memory result) = SECP256R1.staticcall(input);
        require(success && result.length > 0, "Verification failed");
        return abi.decode(result, (uint256)) == 1;
    }

    struct ModalInput {
        uint8 inputType;
        bytes data;
        string uri;
        bytes32 contentHash;
        uint32 param1;
        uint32 param2;
        bool encrypted;
    }

    struct OutputConfig {
        uint8 outputType;
        uint32 maxParam1;
        uint32 maxParam2;
        uint32 maxParam3;
        bool encryptOutput;
        uint16 numInferenceSteps;
        uint16 guidanceScaleX100;
        uint32 seed;
        uint8 fps;
        string negativePrompt;
    }

    struct StorageRef {
        string platform;
        string path;
        string keyRef;
    }

    struct SovereignStorageRef {
        string platform;
        string path;
        string keyRef;
    }

    struct SovereignAgentParams {
        address executor;
        uint256 ttl;
        bytes userPublicKey;
        uint64 pollIntervalBlocks;
        uint64 maxPollBlock;
        string taskIdMarker;
        address deliveryTarget;
        bytes4 deliverySelector;
        uint256 deliveryGasLimit;
        uint256 deliveryMaxFeePerGas;
        uint256 deliveryMaxPriorityFeePerGas;
        uint16 agentType;
        string prompt;
        bytes encryptedSecrets;
        SovereignStorageRef convoHistory;
        SovereignStorageRef output;
        SovereignStorageRef[] skills;
        SovereignStorageRef systemPrompt;
        string model;
        string[] tools;
        uint16 maxTurns;
        uint32 maxTokens;
        string rpcUrls;
    }

    struct SovereignScheduleConfig {
        uint32 schedulerGas;
        uint32 frequency;
        uint32 schedulerTtl;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        uint256 value;
    }

    struct SovereignRollingConfig {
        uint32 windowNumCalls;
        uint16 rolloverThresholdBps;
        uint16 rolloverRetryEveryCalls;
    }

    function _buildModalInput(string memory prompt) internal pure returns (ModalInput[] memory) {
        ModalInput[] memory inputs = new ModalInput[](1);
        inputs[0] = ModalInput({
            inputType: 0,
            data: bytes(prompt),
            uri: "",
            contentHash: bytes32(0),
            param1: 0,
            param2: 0,
            encrypted: false
        });
        return inputs;
    }

    function _buildOutputConfig(uint32 width, uint32 height) internal pure returns (OutputConfig memory) {
        return OutputConfig({
            outputType: 1,
            maxParam1: width,
            maxParam2: height,
            maxParam3: 0,
            encryptOutput: false,
            numInferenceSteps: 0,
            guidanceScaleX100: 0,
            seed: 0,
            fps: 0,
            negativePrompt: ""
        });
    }

    function _callImagePrecompile(
        address executor,
        bytes[] memory encryptedSecrets,
        uint256 ttl,
        string memory model,
        ModalInput[] memory inputs,
        OutputConfig memory output,
        StorageRef memory outputStorageRef
    ) internal returns (bytes memory) {
        PrecompileInput memory pi;
        pi.executor = executor;
        pi.encryptedSecrets = encryptedSecrets;
        pi.ttl = ttl;
        pi.allowedQueueIdx = new bytes[](0);
        pi.allowedDelegate = bytes("");
        pi.gas = uint64(5);
        pi.value = uint64(1000);
        pi.taskId = "IMAGE_TASK_ID";
        pi.revertAddress = address(this);
        pi.callbackSelector = this.onImageReady.selector;
        pi.callbackGasLimit = 500_000;
        pi.feeMaxGas = 1e9;
        pi.feeMaxGasPrice = 1e8;
        pi.feeToken = 0;
        pi.model = model;
        pi.inputs = inputs;
        pi.output = output;
        pi.outputStorageRef = outputStorageRef;

        (bool ok, bytes memory result) = IMAGE_PRECOMPILE.call(abi.encode(pi));
        require(ok, "Image precompile call failed");
        return result;
    }

    struct PrecompileInput {
        address executor;
        bytes[] encryptedSecrets;
        uint256 ttl;
        bytes[] allowedQueueIdx;
        bytes allowedDelegate;
        uint64 gas;
        uint64 value;
        string taskId;
        address revertAddress;
        bytes4 callbackSelector;
        uint256 callbackGasLimit;
        uint256 feeMaxGas;
        uint256 feeMaxGasPrice;
        uint256 feeToken;
        string model;
        ModalInput[] inputs;
        OutputConfig output;
        StorageRef outputStorageRef;
    }

    function requestImage(
        address executor,
        uint256 ttl,
        string calldata prompt,
        string calldata model,
        uint32 width,
        uint32 height,
        StorageRef calldata outputStorageRef,
        bytes[] calldata encryptedSecrets
    ) external onlyOwner returns (bytes32) {
        ModalInput[] memory inputs = _buildModalInput(prompt);
        OutputConfig memory output = _buildOutputConfig(width, height);
        bytes memory result = _callImagePrecompile(executor, encryptedSecrets, ttl, model, inputs, output, outputStorageRef);

        bytes32 jobId = keccak256(result);
        _requests[jobId] = ImageRequest({
            user: msg.sender,
            prompt: prompt,
            uri: "",
            contentHash: bytes32(0),
            fulfilled: false,
            failed: false,
            errorMessage: ""
        });
        requestIds.push(jobId);

        emit ImageRequested(jobId, msg.sender, prompt);
        return jobId;
    }

    struct CallbackData {
        bool hasError;
        string outputUri;
        bytes32 contentHash;
        string errorMsg;
    }

    function _decodeCallbackResponse(bytes calldata responseData) internal pure returns (CallbackData memory) {
        (
            bool hasError,
            ,
            string memory outputUri,
            bytes32 contentHash,
            ,
            ,
            ,
            ,
            string memory errorMsg
        ) = abi.decode(
            responseData,
            (bool, bytes, string, bytes32, bool, uint32, uint32, uint32, string)
        );
        return CallbackData(hasError, outputUri, contentHash, errorMsg);
    }

    function onImageReady(bytes32 jobId, bytes calldata responseData) external onlyAsyncDelivery {
        ImageRequest storage req = _requests[jobId];
        require(!req.fulfilled, "Already fulfilled");

        CallbackData memory cb = _decodeCallbackResponse(responseData);

        if (cb.hasError) {
            req.failed = true;
            req.errorMessage = cb.errorMsg;
            req.fulfilled = true;
            emit ImageFailed(jobId, cb.errorMsg);
            return;
        }

        req.uri = cb.outputUri;
        req.contentHash = cb.contentHash;
        req.fulfilled = true;
        emit ImageReady(jobId, req.user, cb.outputUri);
    }

    function getRegisteredKey(address user) external view returns (bytes32 x, bytes32 y) {
        P256Key storage key = _registeredKeys[user];
        return (key.x, key.y);
    }

    function getRequest(bytes32 jobId) external view returns (ImageRequest memory) {
        return _requests[jobId];
    }

    function getRequestCount() external view returns (uint256) {
        return requestIds.length;
    }

    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function scheduleAutomaticImage(
        string calldata basePrompt,
        uint32 gasLimit,
        uint256 maxFeePerGas,
        uint32 numCalls
    ) external onlyOwner {
        require(activeScheduleId == 0, "Already scheduled");

        bytes memory data = abi.encodeWithSelector(
            this.executeScheduledImage.selector,
            uint256(0)
        );

        scheduleBasePrompt = basePrompt;

        activeScheduleId = IScheduler(SCHEDULER).schedule(
            data,
            gasLimit,
            uint32(block.number) + 1,
            numCalls,
            1,
            200,
            maxFeePerGas,
            0,
            0,
            address(this),
            address(this)
        );

        emit AutoScheduleSet(activeScheduleId, 1, numCalls, basePrompt);
    }

    function executeScheduledImage(uint256 executionIndex) external onlyScheduler {
        lastScheduledExecution = block.timestamp;

        string memory prompt = string.concat(scheduleBasePrompt, " | ", _uint2str(block.timestamp));

        ModalInput[] memory inputs = _buildModalInput(prompt);
        OutputConfig memory output = _buildOutputConfig(1024, 1024);
        StorageRef memory storageRef = scheduleOutputRef;

        bytes[] memory emptySecrets = new bytes[](0);
        bytes memory result = _callImagePrecompile(
            RITUAL_WALLET,
            emptySecrets,
            300,
            "flux-schnell",
            inputs,
            output,
            storageRef
        );

        bytes32 jobId = keccak256(result);
        _requests[jobId] = ImageRequest({
            user: address(0),
            prompt: prompt,
            uri: "",
            contentHash: bytes32(0),
            fulfilled: false,
            failed: false,
            errorMessage: ""
        });
        requestIds.push(jobId);
        scheduledImageCount++;

        emit ImageRequested(jobId, address(0), prompt);
        emit ScheduledImageCreated(executionIndex, jobId, prompt);
    }

    function setScheduleOutputStorage(StorageRef calldata ref) external onlyOwner {
        scheduleOutputRef = ref;
    }

    function cancelAutomaticSchedule() external onlyOwner {
        require(activeScheduleId != 0, "No active schedule");
        IScheduler(SCHEDULER).cancel(activeScheduleId);
        activeScheduleId = 0;
        emit AutoScheduleCancelled(activeScheduleId);
    }

    function setScheduleBasePrompt(string calldata basePrompt) external onlyOwner {
        scheduleBasePrompt = basePrompt;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Sovereign Agent (0x080C) Lifecycle
    // ═══════════════════════════════════════════════════════════════

    function configureFundAndStart(
        SovereignAgentParams calldata p,
        SovereignScheduleConfig calldata s,
        SovereignRollingConfig calldata r,
        uint256 lockDuration
    ) external payable onlyOwner returns (uint256 callId) {
        _configure(p, s, r);
        if (msg.value > 0) {
            IRitualWallet(RITUAL_WALLET).depositFor{value: msg.value}(address(this), lockDuration);
        }
        return _armRollingWindow(r.windowNumCalls);
    }

    function _configure(
        SovereignAgentParams calldata p,
        SovereignScheduleConfig calldata s,
        SovereignRollingConfig calldata r
    ) internal {
        if (wakeMode != SovereignWakeMode.NONE) revert AlreadyRunning();
        params = p;
        scheduleConfig = s;
        rollingConfig = r;
        wakeMode = SovereignWakeMode.ROLLING_FIXED_WINDOW;
        configured = true;
        hasStartConfig = true;
        thresholdIndex = _computeThresholdIndex(r.windowNumCalls, r.rolloverThresholdBps);
        emit SovereignConfigured(owner);
    }

    function _armRollingWindow(uint32 numCalls) internal returns (uint256 callId) {
        bytes memory data = abi.encodeWithSelector(
            this.wakeUp.selector,
            uint256(0),
            uint64(0)
        );
        callId = IScheduler(SCHEDULER).schedule(
            data,
            scheduleConfig.schedulerGas,
            uint32(block.number) + 1,
            numCalls,
            scheduleConfig.frequency,
            scheduleConfig.schedulerTtl,
            scheduleConfig.maxFeePerGas,
            scheduleConfig.maxPriorityFeePerGas,
            scheduleConfig.value,
            address(this),
            address(this)
        );
        activeCallId = callId;
        activeNumCalls = numCalls;
        currentSeriesId = nextSeriesId++;
        emit SovereignStarted(callId, numCalls, scheduleConfig.frequency);
    }

    function _callSovereignPrecompile(uint256 executionIndex, uint64 seriesId) internal {
        bytes memory input = getSovereignAgentInput();
        (bool ok, bytes memory output) = SOVEREIGN_AGENT_PRECOMPILE.call(input);
        if (!ok) revert SovereignCallFailed();
        emit SovereignInvoked(executionIndex, seriesId, output);
    }

    function getSovereignAgentInput() internal view returns (bytes memory) {
        return abi.encode(params);
    }

    function wakeUp(uint256 executionIndex, uint64 seriesId) external onlyScheduler {
        if (wakeMode == SovereignWakeMode.NONE) return;

        if (seriesId == pendingSeriesId && pendingCallId != 0) {
            activeCallId = pendingCallId;
            activeNumCalls = rollingConfig.windowNumCalls;
            currentSeriesId = pendingSeriesId;
            pendingCallId = 0;
            pendingSeriesId = 0;
        }

        if (seriesId != currentSeriesId) return;

        if (pendingCallId == 0 && executionIndex >= thresholdIndex) {
            _tryScheduleSuccessor();
        }

        _callSovereignPrecompile(executionIndex, seriesId);
    }

    function _tryScheduleSuccessor() internal {
        uint64 successorSeriesId = nextSeriesId++;
        uint256 successorCallId = IScheduler(SCHEDULER).schedule(
            abi.encodeWithSelector(this.wakeUp.selector, uint256(0), successorSeriesId),
            scheduleConfig.schedulerGas,
            uint32(block.number) + 1,
            rollingConfig.windowNumCalls,
            scheduleConfig.frequency,
            scheduleConfig.schedulerTtl,
            scheduleConfig.maxFeePerGas,
            scheduleConfig.maxPriorityFeePerGas,
            scheduleConfig.value,
            address(this),
            address(this)
        );
        pendingCallId = successorCallId;
        pendingSeriesId = successorSeriesId;
    }

    function _tryCancelRetiredCall() internal {
        uint256 retiredCallId = activeCallId;
        if (retiredCallId != 0) {
            IScheduler(SCHEDULER).cancel(retiredCallId);
        }
    }

    function _computeThresholdIndex(uint32 numCalls, uint16 thresholdBps) internal pure returns (uint32) {
        uint256 thresholdCount = (uint256(numCalls) * uint256(thresholdBps) + 9999) / 10000;
        if (thresholdCount == 0) thresholdCount = 1;
        return uint32(thresholdCount - 1);
    }

    function _stop() internal {
        if (activeCallId != 0) {
            IScheduler(SCHEDULER).cancel(uint256(activeCallId));
            activeCallId = 0;
        }
        if (pendingCallId != 0) {
            IScheduler(SCHEDULER).cancel(uint256(pendingCallId));
            pendingCallId = 0;
        }
        wakeMode = SovereignWakeMode.NONE;
    }

    function stop() external onlyOwner {
        if (wakeMode == SovereignWakeMode.NONE) return;
        _stop();
        emit SovereignStopped();
    }

    function restart() external onlyOwner returns (uint256 callId) {
        if (!hasStartConfig) revert NotConfigured();
        if (wakeMode != SovereignWakeMode.NONE) {
            _stop();
        }
        wakeMode = SovereignWakeMode.ROLLING_FIXED_WINDOW;
        callId = _armRollingWindow(rollingConfig.windowNumCalls);
        emit SovereignRestarted(callId);
    }

    function onSovereignAgentResult(bytes32 jobId, bytes calldata result) external onlyAsyncDelivery {
        emit SovereignResult(jobId, result);
    }
}
