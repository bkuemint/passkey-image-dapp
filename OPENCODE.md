# OPENCODE.md — Learning Log

## Session Context
- **Date**: 2026-06-25
- **Environment**: Windows (PowerShell 5.1), Node v24.18.0, npm 11.16.0
- **Foundry**: Installed locally (not available in agent's env)

## Deployment
- **Contract**: PasskeyImageConsumer
- **Address**: `0xe8D3139f5fCEC2085Fcf01Dde99A3Ba53Ab1Ac18`
- **Tx Hash**: `0x4727c858e4c2321711565a8fbe72cc049c9f5c3431a5179e68702cc569d769b0`
- **Block**: 37,256,264
- **Chain**: Ritual Chain (ID 1979)
- **Status**: `forge build` ✓, `forge test` (7/7 pass) ✓, deployed ✓

## Stack-Too-Deep: Root Cause (RESOLVED)

The `via_ir` IR pipeline in Solidity was generating excessive Yul variables from two sources:

### Primary cause: 18-arg `abi.encode` in `_callImagePrecompile`
Each argument to `abi.encode` becomes a separate Yul stack variable. With 18 arguments (including dynamic types like `bytes[]`, `string`, `ModalInput[]`), the Yul optimizer hit 17+ simultaneous stack slots during the encoding step.

**Fix**: Packed all 18 fields into a `PrecompileInput` memory struct, assigned fields one-by-one (memory writes, not stack pushes), then called `abi.encode(pi)` with a single struct argument.

### Secondary cause: 9-value `abi.decode` in `_decodeCallbackResponse`
Decoding into 9 individual variables created similar stack pressure.

**Fix**: Moved the decode into an internal helper function (isolated stack frame), returning only the 4 needed fields via a `CallbackData` struct.

### Contributing factor: public struct-returning mappings
`mapping(bytes32 => ImageRequest) public requests` and `mapping(address => P256Key) public registeredKeys` auto-generated getters that return 7-field and 2-field structs respectively. The IR pipeline's getter code added further Yul stack pressure.

**Fix**: Made both mappings private, added explicit getter functions (`getRequest`, `getRegisteredKey`) that return structs/manual tuples.

### Key insight
The struct-based approach works because passing a struct pointer to `abi.encode` is a single stack value, and the encoder reads fields from memory via offsets rather than pushing each field individually. This reduces Yul variables from O(N) to O(1).

## Precompiles Used

### 1. SECP256R1 (0x0100) — Passkey Verification
- **Address**: `0x0000000000000000000000000000000000000100`
- **Type**: Synchronous, single-block
- **Usage**: `staticcall` with `abi.encode(pubkey, message, signature)`
- **Input**: `(bytes, bytes, bytes)` — uncompressed pubkey (0x04 || x || y, 65 bytes), message, signature
- **Output**: `uint256` — 1 for valid, 0 for invalid
- **Notes**: Must pass compressed 65-byte key (0x04 prefix). The `getPublicKey()` from `AuthenticatorAttestationResponse` returns a DER-encoded key — we slice the last 65 bytes to extract the uncompressed P-256 key.

### 2. Image Precompile (0x0818) — AI Image Generation
- **Address**: `0x0000000000000000000000000000000000000818`
- **Type**: Long-running async (2-phase delivery)
- **Phase 1**: Submit request via `call(input)` — returns response data, `jobId = keccak256(result)`
- **Phase 2**: `AsyncDelivery` (0x5A16214f) calls `onImageReady(jobId, responseData)` on the contract
- **Restriction**: Only 1 SPC per tx (but SECP256R1 is sync precompile, not SPC, so this doesn't conflict)
- **Restriction**: Sender lock — only 1 async job per EOA at a time

#### Image Precompile Input Encoding (Phase 1)
The `requestImage` function encodes these fields to the precompile via `abi.encode(...)`:
1. `executor` (address) — executor address, currently `RITUAL_WALLET`
2. `encryptedSecrets` (bytes[]) — empty for now
3. `ttl` (uint256) — 300 blocks
4. `allowedQueueIdx` (bytes[]) — empty
5. `allowedDelegate` (bytes) — empty bytes
6. `gas` (uint64) — 5
7. `value` (uint64) — 1000
8. `taskId` (string) — "IMAGE_TASK_ID"
9. `revertAddress` (address) — `address(this)`
10. `callbackSelector` (bytes4) — `this.onImageReady.selector`
11. `callbackGasLimit` (uint256) — 500000
12. `feeMaxGas` (uint256) — 1e9
13. `feeMaxGasPrice` (uint256) — 1e8
14. `feeToken` (uint256) — 0 (native RITUAL)
15. `model` (string) — e.g. "flux-schnell"
16. `inputs` (ModalInput[]) — array of 1 input with the prompt text
17. `outputConfig` (OutputConfig) — 1024x1024, outputType 1 (image)
18. `outputStorageRef` (StorageRef) — platform "gcs", path "passkey-image-dapp-outputs"

#### Callback Response Format (Phase 2)
The response data decodes as: `(bool hasError, bytes, string outputUri, bytes32 contentHash, bool, uint32, uint32, uint32, string errorMsg)`

### 3. RitualWallet (0x532F) — Fee Management
- **Address**: `0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948`
- **Usage**: `deposit(lockDuration)` — fund executor fees for async operations
- **lockDuration**: Must cover the expected operation window. Defaulting to 100000 blocks (~1 week at 2s/block)
- **Only owner** can deposit (controlled by `onlyOwner` modifier)

## Design Decisions

### Passkey → Address Mapping
- Use `keccak256(publicKeyX || publicKeyY)` and take the last 20 bytes as the Ritual address
- This matches how Ethereum derives addresses from secp256k1 keys but adapted for P-256
- The address is deterministic from the passkey — no on-chain registration needed to derive it
- However, the contract still needs `registerKey(x, y)` to store the key for the `authenticate()` function (future use)

### Two-Account Architecture
- **Passkey user**: Has an address (derived from P-256 key), but no RITUAL balance on Ritual Chain
- **Funded submitter**: Wallet `0xf37f26FdB23f2BdD5349188Bb5565Ed3Acd3ff5b` is pre-funded and submits all transactions
- The contract's `requestImage` is `onlyOwner` — only the funded wallet can submit image requests
- The passkey-derived address is stored as `user` in the `ImageRequest` struct for display/query purposes

### Async Polling Strategy
- Frontend polls `getRequest(jobId)` every 3 seconds
- Checks `fulfilled` field — when true, either `uri` (success) or `errorMessage` (failure) is populated
- No event subscription needed (simpler for MVP)
- Poll interval could be increased or switched to `watchContractEvent` for a production version

### Storage Configuration
- Using GCS (Google Cloud Storage) as output platform
- URI conversion: `gs://bucket/path` → `https://storage.googleapis.com/bucket/path`
- Alternative storage platforms: HuggingFace, Pinata (IPFS)
- `keyRef` left empty — GCS public bucket or application default credentials

### Image Model Choices
- `flux-schnell` — fast FLUX model, good for quick generation
- `OutputConfig.outputType = 1` for image output
- 1024x1024 resolution
- Could also use `stable-diffusion-v3` or `dall-e-3` depending on executor support

## Framework Choices

### Contracts
- **Solidity 0.8.20** with `via-ir` optimization enabled
- **Foundry** for build, test, deploy
- **EVM Cancun** target
- No external dependencies (no OpenZeppelin — keeping it minimal)

### Frontend
- **Next.js 14** (App Router)
- **TypeScript** with strict mode
- **viem ^2.17** for blockchain interactions (walletClient + publicClient)
- **Tailwind CSS 3** with custom ritwal color palette (50-950)
- **No wagmi** (keeping it minimal — using viem directly)
- **No RainbowKit/ConnectKit** — passkey is the only auth method

## Key Build Issues & Fixes

| Issue | Root Cause | Fix |
|-------|------------|-----|
| ESLint init fails interactively | Next.js prompts for config | Create `.eslintrc.json` manually |
| TypeScript: BigInt not available | `target: ES2017` doesn't support `300n` literal | Changed to `target: ES2020` |
| TypeScript: `window.ethereum` unknown | Missing global type declaration | Added `lib/global.d.ts` |
| TypeScript: `safeWebAuthnCall` type error | Passing `Promise<T>` directly instead of `() => Promise<T>` | Wrapped in arrow function |
| TypeScript: `writeContract` needs `account` | viem v2 requires explicit account field | Added `account: address` |
| TypeScript: `readContract` result can't be indexed by number | viem v2 returns typed struct, not array | Cast via `as unknown as ImageRequestResult` |
| Forge: `consumer.requests(jobId).fulfilled` fails to compile | Solidity public mapping getters return tuples, not structs — cannot use `.member` access | Use `consumer.getRequest(jobId)` which returns the struct type with named member access |
| Forge: "stack too deep by 2 slots" in `requestImage` | 18 arguments to `abi.encode` + ~6 local variables exceeded EVM stack depth | Refactored into 3 helpers (`_buildModalInput`, `_buildOutputConfig`, `_callImagePrecompile`), each with its own stack frame |
| Forge: "stack too deep by 2 slots" in `onImageReady` | 9-value abi.decode with 6 local variables in scope | Extracted decode into `_decodeCallbackResponse()` helper + `CallbackData` struct — decode's 9 variables isolated in helper's stack frame; `onImageReady` only sees the 4-field struct |
| Forge: "stack too deep" persisted after `requests` fix | Error unchanged even after `forge clean` | Changed `registeredKeys` from `public` to `private` + added `getRegisteredKey()` returning flat values — still not the root cause |
| Forge: stack-too-deep finally resolved | Struct-returning public mappings AND 18-arg abi.encode / 9-arg abi.decode all contributed | Packed 18 encode args into `PrecompileInput` struct (`abi.encode(pi)`), wrapped 9 decode vars in helper function — each has its own stack frame |
| ESLint: "next/core-web-vitals" not found | `eslint-config-next` not installed | `npm install --save-dev eslint-config-next@14` |
| ESLint v10 incompatible with Next.js 14 | v10 uses flat config only, Next expects eslintrc | Downgraded to `eslint@^8` |

## Persistent "Please install a web3 wallet" Message (UNRESOLVED)

Despite the frontend codebase being fully cleaned of any wallet-detection checks, the "please install a web3 wallet" / "please connect a web3 wallet" message continues to appear on the live Vercel deployment after image generation is attempted.

### Investigation so far

1. **Exhaustive codebase search**: Zero references to `window.ethereum`, `custom(window`, `requestAddresses`, `"web3 wallet"`, `"MetaMask"`, or `"install.*wallet"` remain in any runtime code. Only `lib/global.d.ts` declares the `ethereum` type annotation (zero runtime effect, stripped at compile time).

2. **Build output**: `next build` completes successfully — no compilation errors, no type errors related to wallet providers.

3. **Deployment**: Vercel deployment was rebuilt with cache cleared. The API routes (`/api/submit-request`, `/api/owner-action`) show as `ƒ (Dynamic) server-rendered on demand` in the build output, confirming they exist on the server.

4. **Passkey login works**: The user can successfully create/log in with a passkey. The `userAddress` state is set, and `PromptInput` renders.

### Next debugging step

The error is happening at **request-time** (not build-time). The user should:

1. Open browser DevTools (F12) on the live site
2. Go to the **Console** tab — look for any `alert()` message, uncaught error, or 500 response from the API
3. Go to the **Network** tab — find the `POST /api/submit-request` call, inspect its **Response** tab
4. The API route returns structured JSON errors. The actual error text will reveal whether:
   - `PRIVATE_KEY` is not configured on the server (the API returns `"PRIVATE_KEY not configured on server"`)
   - The RPC call itself is failing
   - Some other runtime failure

Since the frontend `submitRequest` flow now calls `fetch('/api/submit-request')`, any "install a web3 wallet" message the user sees must be coming from the server response or a browser-level wallet prompt, not from client-side code.

## TODO / Known Gaps

1. **Executor selection**: Currently using `RITUAL_WALLET` as placeholder. Should query `TEEServiceRegistry` (0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F) for executors with capability 7 (IMAGE_CALL). See ritual-dapp-precompiles skill for registry ABI.
2. **ECIES encryption**: For encryptedSecrets, need ECIES with 12-byte nonce. See ritual-dapp-secrets skill.
3. **Passkey `authenticate()`**: The `authenticate()` function in the contract is implemented but not called from the frontend. Passkey auth currently works by storing/retrieving from `localStorage` — the on-chain `authenticate()` could be used for more secure server-side verification later.
4. **Contract fee deposit**: Before deploying, the contract needs RITUAL deposited via `depositFees{value: ...}(lockDuration)` to cover executor costs.
5. **GCS bucket setup**: The `outputStorageRef.path = "passkey-image-dapp-outputs"` expects a pre-configured GCS bucket or HuggingFace repo. Need to verify platform availability.
6. **Concurrent requests**: Sender lock restricts to 1 async job per EOA. If the funded wallet submits multiple requests simultaneously, the second will fail. Consider using multiple funded EOAs or a relayer.
7. **TTL value**: Currently set to 300 blocks (~10 min at 2s/block). May need adjustment based on actual generation time.
8. **Contract compilation**: Foundry not available in this environment. Must run `forge build` locally before deployment.
9. **Production hardening**: No reentrancy guards, access control is minimal (`onlyOwner`), no circuit breakers. Fine for MVP.

## Ritual-Specific Nuances

- **Precompile is NOT payable** — the image precompile (0x0818) does not accept value directly. Fees are managed through RitualWallet.
- **Sender lock** — the SPC (Scheduled Precompile Call) model means only one async job per EOA can be active at a time. Submit sequentially or use different submitter addresses.
- **Only 1 SPC per TX** — cannot combine multiple async precompile calls in one transaction. Our design only uses 1 async precompile (image) so this is fine.
- **ECIES nonce = 12 bytes** — if encrypted secrets are needed, the nonce must be exactly 12 bytes.
- **Phase 2 callback guard** — only `AsyncDelivery` (0x5A16214f) can invoke `onImageReady`. The `onlyAsyncDelivery` modifier enforces this.
- **Attestation type "none"** — we use `attestation: 'none'` in WebAuthn creation. The dApp does not verify the attestation statement, only extracts the P-256 public key.
- **RP ID = window.location.hostname** — WebAuthn requires the RP ID to match the current domain. For local development, this will be `localhost`. For production, it must match the deployed domain.
