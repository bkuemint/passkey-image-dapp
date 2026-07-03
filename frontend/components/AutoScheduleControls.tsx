'use client';

import { useState, useEffect, useCallback } from 'react';
import { createPublicClient, http } from 'viem';
import { ritualChain } from '@/lib/chain';
import { consumerAbi } from '@/lib/contract';

const CONSUMER_ADDRESS = (process.env.NEXT_PUBLIC_CONSUMER_ADDRESS || '') as `0x${string}`;

export default function AutoScheduleControls() {
  const [isOwner, setIsOwner] = useState(false);
  const [activeId, setActiveId] = useState<bigint>(0n);
  const [imageCount, setImageCount] = useState<bigint>(0n);
  const [lastExec, setLastExec] = useState<bigint>(0n);
  const [ownerAddr, setOwnerAddr] = useState<string>('');
  const [basePrompt, setBasePrompt] = useState('Daily Ritual Chain image');
  const [sending, setSending] = useState(false);

  const refreshState = useCallback(async () => {
    try {
      const publicClient = createPublicClient({ chain: ritualChain, transport: http() });

      const [owner, id, count, last] = await Promise.all([
        publicClient.readContract({ address: CONSUMER_ADDRESS, abi: consumerAbi, functionName: 'owner' }) as Promise<string>,
        publicClient.readContract({ address: CONSUMER_ADDRESS, abi: consumerAbi, functionName: 'activeScheduleId' }),
        publicClient.readContract({ address: CONSUMER_ADDRESS, abi: consumerAbi, functionName: 'scheduledImageCount' }),
        publicClient.readContract({ address: CONSUMER_ADDRESS, abi: consumerAbi, functionName: 'lastScheduledExecution' }),
      ]);

      setOwnerAddr(owner);
      setActiveId(id as bigint);
      setImageCount(count as bigint);
      setLastExec(last as bigint);

      const signerRes = await fetch('/api/owner-action');
      if (signerRes.ok) {
        const { signer } = await signerRes.json();
        setIsOwner(signer.toLowerCase() === owner.toLowerCase());
      }
    } catch { /* ignore */ }
  }, []);

  useEffect(() => { refreshState(); }, [refreshState]);

  const handleStart = async () => {
    setSending(true);
    try {
      const publicClient = createPublicClient({ chain: ritualChain, transport: http() });
      const gasPrice = await publicClient.getGasPrice();

      const res = await fetch('/api/owner-action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          functionName: 'scheduleAutomaticImage',
          args: [basePrompt, 500_000, gasPrice.toString(), 730],
        }),
      });

      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || 'Start failed');
      }

      await refreshState();
    } catch (err) {
      alert(`Start failed: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setSending(false);
    }
  };

  const handleStop = async () => {
    setSending(true);
    try {
      const res = await fetch('/api/owner-action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          functionName: 'cancelAutomaticSchedule',
          args: [],
        }),
      });

      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || 'Stop failed');
      }

      await refreshState();
    } catch (err) {
      alert(`Stop failed: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setSending(false);
    }
  };

  const scheduleActive = activeId > 0n;
  const lastExecDate = lastExec > 0n
    ? new Date(Number(lastExec) * 1000).toLocaleString()
    : null;

  if (!isOwner) {
    if (scheduleActive) {
      return (
        <div className="w-full rounded-xl border border-ritual-700 bg-black/20 p-4 text-sm">
          <p className="opacity-60">Auto-generation is running ({imageCount.toString()} images generated so far)</p>
        </div>
      );
    }
    return null;
  }

  return (
    <div className="w-full rounded-xl border border-ritual-700 bg-black/20 p-4">
      <h3 className="text-sm font-semibold mb-3">Auto-Generation (Owner)</h3>

      {scheduleActive ? (
        <div className="flex flex-col gap-2 text-sm">
          <p>Schedule ID: <span className="font-mono">{activeId.toString()}</span></p>
          <p>Images generated: {imageCount.toString()}</p>
          {lastExecDate && <p>Last execution: {lastExecDate}</p>}
          <button
            onClick={handleStop}
            disabled={sending}
            className="self-start bg-red-700 hover:bg-red-800 disabled:opacity-40 text-white font-medium px-4 py-1.5 rounded-lg text-sm transition-colors"
          >
            {sending ? 'Stopping...' : 'Stop Auto-Generation'}
          </button>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <div>
            <label className="text-xs opacity-60 block mb-1">Base prompt template</label>
            <input
              value={basePrompt}
              onChange={e => setBasePrompt(e.target.value)}
              className="w-full rounded-lg border border-ritual-700 bg-transparent p-2 text-sm focus:outline-none focus:ring-2 focus:ring-ritual-500"
            />
            <p className="text-xs opacity-40 mt-1">Timestamp is appended automatically</p>
          </div>
          <button
            onClick={handleStart}
            disabled={sending || !basePrompt.trim()}
            className="self-start bg-ritual-600 hover:bg-ritual-700 disabled:opacity-40 text-white font-medium px-4 py-1.5 rounded-lg text-sm transition-colors"
          >
            {sending ? 'Starting...' : 'Start Auto-Generation'}
          </button>
        </div>
      )}
    </div>
  );
}
