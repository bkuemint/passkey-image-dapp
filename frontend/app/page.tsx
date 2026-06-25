'use client';

import { useState } from 'react';
import PasskeyLogin from '@/components/PasskeyLogin';
import PromptInput from '@/components/PromptInput';
import ImageDisplay from '@/components/ImageDisplay';
import AutoScheduleControls from '@/components/AutoScheduleControls';

export default function Home() {
  const [userAddress, setUserAddress] = useState<`0x${string}` | null>(null);
  const [jobIds, setJobIds] = useState<{ jobId: `0x${string}`; prompt: string }[]>([]);

  const handleLogin = (addr: `0x${string}`) => {
    setUserAddress(addr);
  };

  const handleRequest = (jobId: `0x${string}`, prompt: string) => {
    setJobIds(prev => [{ jobId, prompt }, ...prev]);
  };

  const handleLogout = () => {
    setUserAddress(null);
    setJobIds([]);
  };

  return (
    <main className="w-full max-w-2xl flex flex-col items-center gap-8 py-8">
      <h1 className="text-3xl font-bold text-center">
        Passkey Image dApp
      </h1>
      <p className="text-center text-sm opacity-70 -mt-6">
        Log in with FaceID &bull; Generate with AI &bull; On Ritual Chain
      </p>

      <PasskeyLogin
        userAddress={userAddress}
        onLogin={handleLogin}
        onLogout={handleLogout}
      />

      {userAddress && (
        <PromptInput userAddress={userAddress} onRequest={handleRequest} />
      )}

      <AutoScheduleControls />

      {jobIds.length > 0 && (
        <section className="w-full flex flex-col gap-6">
          <h2 className="text-xl font-semibold">Generated Images</h2>
          {jobIds.map(({ jobId, prompt }) => (
            <ImageDisplay key={jobId} jobId={jobId} prompt={prompt} />
          ))}
        </section>
      )}
    </main>
  );
}
