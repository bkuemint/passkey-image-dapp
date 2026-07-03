'use client';

import { useState, useCallback } from 'react';
import { createPublicClient, http } from 'viem';
import { ritualChain } from '@/lib/chain';
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
    setSubmitting(true);
    try {
      const res = await fetch('/api/submit-request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt }),
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.error || 'Failed to submit request');
      }

      return { jobId: data.jobId as `0x${string}` };
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
