'use client';

import { useState, useCallback } from 'react';
import { createPublicClient, createWalletClient, http, custom } from 'viem';
import { ritualChain, PRECOMPILES, ADDRESSES } from '@/lib/chain';
import { consumerAbi } from '@/lib/contract';

const CONSUMER_ADDRESS = (process.env.NEXT_PUBLIC_CONSUMER_ADDRESS || '') as `0x${string}`;

interface ImageRequestResult {
  user: string;
  prompt: string;
  uri: string;
  contentHash: string;
  fulfilled: boolean;
  failed: boolean;
  errorMessage: string;
}

interface RequestImageResult {
  jobId: `0x${string}`;
}

export function usePasskeyImage() {
  const [submitting, setSubmitting] = useState(false);

  const submitRequest = useCallback(async (prompt: string): Promise<RequestImageResult | null> => {
    if (typeof window === 'undefined' || !window.ethereum) {
      alert('Please install a Web3 wallet (e.g. MetaMask) to submit transactions.');
      return null;
    }

    setSubmitting(true);
    try {
      const walletClient = createWalletClient({
        chain: ritualChain,
        transport: custom(window.ethereum!),
      });

      const [address] = await walletClient.requestAddresses();

      const executor = ADDRESSES.RITUAL_WALLET;

      const ttl = 300n;

      const width = 1024;
      const height = 1024;

      const outputStorageRef = {
        platform: 'gcs',
        path: 'passkey-image-dapp-outputs',
        keyRef: '',
      };

      const encryptedSecrets: `0x${string}`[] = [];

      const hash = await walletClient.writeContract({
        account: address,
        address: CONSUMER_ADDRESS,
        abi: consumerAbi,
        functionName: 'requestImage',
        args: [executor, ttl, prompt, 'flux-schnell', width, height, outputStorageRef, encryptedSecrets],
      });

      const publicClient = createPublicClient({
        chain: ritualChain,
        transport: http(),
      });

      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      const requestedLog = receipt.logs.find(
        log => log.address.toLowerCase() === CONSUMER_ADDRESS.toLowerCase()
      );

      const jobId = requestedLog?.topics?.[1] as `0x${string}` | undefined;

      if (!jobId) {
        const eventSig = '0x' + Array(64).fill('0').join('');
        throw new Error('Could not extract jobId from transaction receipt');
      }

      return { jobId };
    } catch (err) {
      console.error('Submit error:', err);
      alert(`Transaction failed: ${err instanceof Error ? err.message : String(err)}`);
      return null;
    } finally {
      setSubmitting(false);
    }
  }, []);

  const pollRequest = useCallback(async (jobId: `0x${string}`): Promise<ImageRequestResult | null> => {
    try {
      const publicClient = createPublicClient({
        chain: ritualChain,
        transport: http(),
      });

      const result = await publicClient.readContract({
        address: CONSUMER_ADDRESS,
        abi: consumerAbi,
        functionName: 'getRequest',
        args: [jobId],
      });

      const r = result as unknown as ImageRequestResult;
      return r;
    } catch (err) {
      console.error('Poll error:', err);
      return null;
    }
  }, []);

  return { submitRequest, pollRequest, submitting };
}
