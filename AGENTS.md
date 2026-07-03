# AGENTS.md — Passkey Image dApp

## Project Overview

A lightweight dApp on Ritual Chain where users log in with a passkey (FaceID/TouchID — no wallet or seed phrase needed), type a prompt, and generate an AI image using the on-chain image precompile (0x0818). The funded wallet `0xf37f26FdB23f2BdD5349188Bb5565Ed3Acd3ff5b` is used for gas/tx submission.

## Architecture

```
┌─────────────┐     WebAuthn API     ┌──────────────────┐
│   Browser    │ ◄──────────────────► │  P-256 Secure     │
│  (Next.js)   │                      │  Enclave (TPM)    │
│              │                      │  (FaceID/TouchID) │
│  Page         │                                         │
│  ├─PasskeyLogin│  ── create/reg key                      │
│  ├─PromptInput │  ── submit prompt                        │
│  └─ImageDisplay│  ── poll & render                        │
└──────┬───────┘                                          │
       │                                                   │
       │  walletClient.writeContract()                      │
       ▼                                                   │
┌──────────────────────────────────────────┐               │
│  PasskeyImageConsumer  (Solidity)        │               │
│                                          │               │
│  registerKey(x, y)  ◄── stores P-256 pub │               │
│  requestImage(...)  ◄── calls 0x0818     │               │
│  onImageReady(...)  ◄── callback from     │               │
│                         AsyncDelivery     │               │
│  getRequest(jobId)  ◄── read status/uri  │               │
└──────────┬───────────────────────────────┘               │
           │                                               │
           │  staticcall(0x0100)   │  call(0x0818)          │
           ▼                       ▼                        │
┌──────────────────┐  ┌──────────────────────┐             │
│ SECP256R1        │  │ Image Precompile      │             │
│ Precompile 0x0100│  │ Precompile 0x0818      │             │
│ (sync, P-256     │  │ (long-running async,   │             │
│  verify)         │  │  2-phase delivery)     │             │
└──────────────────┘  └──────────┬───────────┘             │
                                 │                           │
                                 ▼                           │
                        ┌──────────────────┐               │
                        │ AsyncDelivery     │               │
                        │ 0x5A16214f       │               │
                        │ (Phase 2:         │               │
                        │  onImageReady)    │               │
                        └──────────────────┘               │
                                 │                           │
                                 ▼                           │
                        ┌──────────────────┐               │
                        │ GCS / HuggingFace │               │
                        │ (output storage)  │               │
                        └──────────────────┘               │
```

## File Map

```
passkey-image-dapp/
├── AGENTS.md                     ← this file
├── OPENCODE.md                   ← learning log
├── .env.example                  ← env vars template
├── README.md                     ← user docs
│
├── .ritual-build/
│   └── progress.json             ← build checkpoint
│
├── contracts/
│   ├── foundry.toml              ← Foundry config (Ritual RPC)
│   ├── src/
│   │   └── PasskeyImageConsumer.sol   ← main contract
│   ├── test/
│   │   └── PasskeyImageConsumer.t.sol  ← Foundry tests
│   └── script/
    │       ├── Deploy.s.sol          ← deploy script
    │       ├── Activate.s.sol        ← activate sovereign agent
    │       ├── encrypt-secret.cjs    ← ECIES encrypt helper (via ffi, Windows-unsafe)
    │       └── prepare-secret.cjs    ← ECIES encrypt + write hex file (offline, Windows-safe)
    │
    └── frontend/
    ├── package.json
    ├── tsconfig.json
    ├── next.config.js
    ├── tailwind.config.ts
    ├── postcss.config.js
    ├── .eslintrc.json
    ├── app/
    │   ├── globals.css
    │   ├── layout.tsx
    │   └── page.tsx              ← main page (login + prompt + images)
    ├── components/
    │   ├── PasskeyLogin.tsx      ← create/login with passkey
    │   ├── PromptInput.tsx       ← prompt textarea + submit
    │   └── ImageDisplay.tsx      ← poll jobId, render image
    ├── hooks/
    │   └── usePasskeyImage.ts    ← submit + poll logic (viem)
    └── lib/
        ├── chain.ts              ← Ritual chain config, addresses
        ├── contract.ts           ← typed ABI (as const)
        ├── webauthn.ts           ← WebAuthn API wrappers
        └── global.d.ts           ← window.ethereum type
```

## Step-by-Step Plan

### Phase 0: Projection (COMPLETE)
- [x] Load all required Ritual skills
- [x] Map user requirements to precompiles
- [x] Create project directory structure

### Phase 1: Write Contracts (COMPLETE)
- [x] `PasskeyImageConsumer.sol` — passkey registration + image request + callback handler
- [x] `PasskeyImageConsumer.t.sol` — 6 tests
- [x] `Deploy.s.sol` — Foundry deploy script
- [x] `foundry.toml` — configured for Ritual Chain

### Phase 2: Write Frontend (COMPLETE)
- [x] `lib/chain.ts` — chain config + address constants
- [x] `lib/contract.ts` — consumer ABI
- [x] `lib/webauthn.ts` — WebAuthn create/authenticate helpers
- [x] `hooks/usePasskeyImage.ts` — submit request + poll for result
- [x] `components/PasskeyLogin.tsx` — passkey creation + login UI
- [x] `components/PromptInput.tsx` — textarea + generate button
- [x] `components/ImageDisplay.tsx` — polling card with image render
- [x] `app/page.tsx` — main page composing all components

### Phase 3: Verify & Build (COMPLETE)
- [x] `npm install` — all deps installed
- [x] `next lint` — passes with 1 warning (`<img>` vs `<Image />`)
- [x] `next build` — production build successful
- [x] `forge build` — compiles successfully
- [x] `forge test` — all 7 tests pass

### Phase 4: Deploy (COMPLETE)
- [x] `forge script Deploy.s.sol --rpc-url ritual --broadcast`
- [x] Deployed at `0xe8D3139f5fCEC2085Fcf01Dde99A3Ba53Ab1Ac18` (tx: `0x4727c858...d769b0`, block: 37,256,264)
- [x] Fund the contract with RITUAL for executor fees (when needed)

### Phase 5: Activate Sovereign Agent (NEXT)

**Windows (two-step — avoids vm.ffi hang):**
- [ ] Read executor address from `cast call 0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F "getServicesByCapability(uint8,bool)((address,address,uint8,bytes,string,bytes32,uint8,bool,bytes32)[])" 0 true --rpc-url ritual`
- [ ] Extract the publicKey hex (3rd field) and run: `node script\prepare-secret.cjs <publicKeyHex>` to generate `script/encrypted-secret.hex`
- [ ] `forge script script\Activate.s.sol --rpc-url ritual --broadcast`

**Non-Windows (single step, vm.ffi works):**
- [ ] `forge script script/Activate.s.sol --rpc-url ritual --broadcast`

### Phase 6: Run Frontend (NEXT)
- [ ] Set `NEXT_PUBLIC_CONSUMER_ADDRESS=0xe8D3139f5fCEC2085Fcf01Dde99A3Ba53Ab1Ac18` in `frontend/.env`
- [ ] `npm run dev` in `frontend/`
- [ ] Open browser, create passkey, generate an image

### Phase 7: E2E Verification (NEXT)
- [ ] Verify passkey registration works
- [ ] Verify image request transaction submits correctly
- [ ] Verify callback handler populates URI
- [ ] Verify image renders from GCS

## Key Design Decisions

1. **Passkey address derivation**: `keccak256(x || y)` — take last 20 bytes — produces the Ritual address from the P-256 public key. No wallet needed.
2. **Two-account model**: Passkey-derived addresses have no RITUAL balance. A funded wallet (`0xf37f26FdB23f2BdD5349188Bb5565Ed3Acd3ff5b`) submits transactions. The contract uses `onlyOwner` for `requestImage`.
3. **Image precompile (0x0818) is long-running async**: Submit in one tx, callback (Phase 2) from `AsyncDelivery` (0x5A16214f) calls `onImageReady`. Frontend polls via `getRequest()` until `fulfilled == true`.
4. **Storage**: `outputStorageRef.platform = "gcs"` with `path = "passkey-image-dapp-outputs"`. Frontend converts `gs://` URIs to `https://storage.googleapis.com/` for rendering.
5. **Image model**: `flux-schnell` (fast FLUX model). 1024x1024 output.
6. **TEE executor**: Selected via `TEEServiceRegistry` (capability 7 = IMAGE_CALL). Currently uses `RITUAL_WALLET` address as placeholder executor.

## Known Issues / Fixes Applied

- ESLint v10 is incompatible with Next.js 14 eslintrc format → downgraded to eslint@8
- `safeWebAuthnCall` expects `() => Promise<T>`, not `Promise<T>` directly → wrapped in arrow function
- `window.ethereum` type missing → added `lib/global.d.ts`
- BigInt literals need ES2020 target → changed `tsconfig.json` `target` from ES2017 to ES2020
- `writeContract` requires explicit `account` field → added `account: address`
- viem v2 returns typed struct from `readContract`, not array → cast via `as unknown as ImageRequestResult`
- `forge build` stack-too-deep under `via_ir` → fixed by packing 18-arg `abi.encode` into a struct (`PrecompileInput`) + moving 9-value `abi.decode` into helper + making struct-returning public mappings private with explicit getters
- `test_callbackError` reverting → fixed by using tuple decode (not struct decode) in `_decodeCallbackResponse` helper
- `test_depositFees` reverting locally → fixed by `vm.etch` mock for RitualWallet precompile address
- `vm.ffi` hangs on Windows when spawning Node.js child process → removed ffi from `Activate.s.sol`; replaced with two-step workflow: (1) run `prepare-secret.cjs` offline to encrypt secrets to a hex file, (2) forge script reads the file via `vm.readFile` + `vm.parseBytes`

## Environment Variables (.env)

```
PRIVATE_KEY=                    # Funded wallet private key for deployment
NEXT_PUBLIC_CONSUMER_ADDRESS=   # Deployed contract address
NEXT_PUBLIC_RPC_URL=            # Ritual Chain RPC (default: https://rpc.ritualfoundation.org)
NEXT_PUBLIC_WS_URL=             # WebSocket URL
ETHERSCAN_API_KEY=              # For contract verification
```

## Ritual Chain Constants

| Component | Address |
|-----------|---------|
| Ritual Wallet | `0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948` |
| AsyncDelivery | `0x5A16214fF555848411544b005f7Ac063742f39F6` |
| TEEServiceRegistry | `0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F` |
| SECP256R1 Precompile | `0x0000000000000000000000000000000000000100` |
| Image Precompile | `0x0000000000000000000000000000000000000818` |
| Chain ID | 1979 |
| RPC | `https://rpc.ritualfoundation.org` |
| Explorer | `https://explorer.ritualfoundation.org` |
| Funded Wallet | `0xf37f26FdB23f2BdD5349188Bb5565Ed3Acd3ff5b` |
