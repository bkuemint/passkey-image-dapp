# Passkey Image dApp

A lightweight dApp on Ritual Chain where users log in with a passkey (FaceID/TouchID), then generate AI images using the on-chain image precompile (0x0818).

## Architecture

- **Contracts**: Solidity (Foundry) — `PasskeyImageConsumer` manages passkey registration, image request submission via 0x0818, and async callback handling
- **Frontend**: Next.js + TypeScript — WebAuthn-based passkey login, prompt input, image display with event polling

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 18
- A wallet funded with RITUAL tokens on Ritual Chain

## Setup

```bash
# Clone and install
cd passkey-image-dapp
cp .env.example .env
# Edit .env: set PRIVATE_KEY, NEXT_PUBLIC_CONSUMER_ADDRESS after deploy

# Install frontend deps
cd frontend && npm install
```

## Deploy

```bash
cd contracts
forge build
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url ritual \
  --broadcast \
  --verify
```

## Run Frontend

```bash
cd frontend
npm run dev
```

## How It Works

1. **Create Passkey** — browser WebAuthn API generates a P-256 key pair stored on device (FaceID/TouchID)
2. **Register** — the passkey's P-256 public key components (x, y) are hashed to derive the user's Ritual address
3. **Submit Prompt** — user types a prompt; the funded wallet sends an image generation request to the image precompile (0x0818)
4. **Poll for Result** — frontend polls the contract until the async callback arrives (Phase 2 delivery from AsyncDelivery)
5. **View Image** — the generated image URI is rendered from GCS (or alternative storage)
