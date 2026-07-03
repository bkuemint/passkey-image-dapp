import { NextRequest, NextResponse } from 'next/server';
import { createPublicClient, createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { ritualChain } from '@/lib/chain';
import { consumerAbi } from '@/lib/contract';
import { encrypt, ECIES_CONFIG } from 'eciesjs';

ECIES_CONFIG.symmetricNonceLength = 12;

const CONSUMER_ADDRESS = (process.env.NEXT_PUBLIC_CONSUMER_ADDRESS || '') as `0x${string}`;
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}` | undefined;

const TEE_SERVICE_REGISTRY = '0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F' as const;
const IMAGE_CAPABILITY = 7;

async function getExecutor() {
  const publicClient = createPublicClient({ chain: ritualChain, transport: http() });
  const services = await publicClient.readContract({
    address: TEE_SERVICE_REGISTRY,
    abi: [{
      name: 'getServicesByCapability',
      type: 'function',
      stateMutability: 'view',
      inputs: [
        { name: 'capability', type: 'uint8' },
        { name: 'activeOnly', type: 'bool' },
      ],
      outputs: [{
        type: 'tuple[]',
        components: [
          { name: 'node', type: 'tuple', components: [
            { name: 'paymentAddress', type: 'address' },
            { name: 'teeAddress', type: 'address' },
            { name: 'teeType', type: 'uint8' },
            { name: 'publicKey', type: 'bytes' },
            { name: 'endpoint', type: 'string' },
            { name: 'certPubKeyHash', type: 'bytes32' },
            { name: 'capability', type: 'uint8' },
          ]},
          { name: 'isValid', type: 'bool' },
          { name: 'workloadId', type: 'bytes32' },
        ],
      }],
    }] as const,
    functionName: 'getServicesByCapability',
    args: [IMAGE_CAPABILITY, true],
  });

  if (services.length === 0) {
    throw new Error('No active image executors found');
  }

  return {
    address: services[0].node.teeAddress,
    publicKey: services[0].node.publicKey as `0x${string}`,
  };
}

function buildSecrets(executorPublicKey: `0x${string}`): `0x${string}`[] {
  if (!process.env.HF_TOKEN) {
    return [];
  }
  const secretsJson = JSON.stringify({
    HF_TOKEN: process.env.HF_TOKEN,
  });
  const encryptedBuffer = encrypt(executorPublicKey.slice(2), Buffer.from(secretsJson));
  return [`0x${encryptedBuffer.toString('hex')}` as `0x${string}`];
}

export async function POST(req: NextRequest) {
  if (!PRIVATE_KEY) {
    return NextResponse.json({ error: 'PRIVATE_KEY not configured on server' }, { status: 500 });
  }
  if (!CONSUMER_ADDRESS) {
    return NextResponse.json({ error: 'NEXT_PUBLIC_CONSUMER_ADDRESS not configured' }, { status: 500 });
  }

  try {
    const { prompt } = await req.json();

    if (!prompt || typeof prompt !== 'string' || !prompt.trim()) {
      return NextResponse.json({ error: 'Invalid or missing prompt' }, { status: 400 });
    }

    const account = privateKeyToAccount(PRIVATE_KEY);
    const walletClient = createWalletClient({ account, chain: ritualChain, transport: http() });

    const executor = await getExecutor();
    const encryptedSecrets = buildSecrets(executor.publicKey);

    const ttl = 300n;
    const width = 1024;
    const height = 1024;

    if (!process.env.HF_REPO) {
      return NextResponse.json({ error: 'HF_REPO not configured' }, { status: 500 });
    }

    const outputStorageRef = {
      platform: 'hf',
      path: `${process.env.HF_REPO}/passkey-image-dapp-outputs`,
      keyRef: encryptedSecrets.length > 0 ? 'HF_TOKEN' : '',
    };

    const hash = await walletClient.writeContract({
      account,
      address: CONSUMER_ADDRESS,
      abi: consumerAbi,
      functionName: 'requestImage',
      args: [executor.address, ttl, prompt.trim(), 'flux-schnell', width, height, outputStorageRef, encryptedSecrets],
    });

    const publicClient = createPublicClient({ chain: ritualChain, transport: http() });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    const requestedLog = receipt.logs.find(
      log => log.address.toLowerCase() === CONSUMER_ADDRESS.toLowerCase()
    );

    const jobId = requestedLog?.topics?.[1] as `0x${string}` | undefined;

    if (!jobId) {
      throw new Error('Could not extract jobId from transaction receipt');
    }

    return NextResponse.json({ jobId });
  } catch (err) {
    console.error('API submit-request error:', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : String(err) },
      { status: 500 }
    );
  }
}
