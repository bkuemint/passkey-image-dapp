'use client';

import { useState, useEffect } from 'react';
import { createPasskey, isPlatformAuthenticatorAvailable, safeWebAuthnCall } from '@/lib/webauthn';

interface Props {
  userAddress: `0x${string}` | null;
  onLogin: (address: `0x${string}`) => void;
  onLogout: () => void;
}

export default function PasskeyLogin({ userAddress, onLogin, onLogout }: Props) {
  const [available, setAvailable] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    isPlatformAuthenticatorAvailable().then(setAvailable);
  }, []);

  const handleCreate = async () => {
    setCreating(true);
    setError(null);

    const result = await safeWebAuthnCall(
      () => createPasskey('user-' + Date.now())
    );

    if ('error' in result) {
      setError(result.error);
      setCreating(false);
      return;
    }

    localStorage.setItem(
      `passkey:${result.result.credentialId}`,
      JSON.stringify({
        x: Array.from(result.result.publicKeyX),
        y: Array.from(result.result.publicKeyY),
        address: result.result.address,
      })
    );

    onLogin(result.result.address);
    setCreating(false);
  };

  const handleLogin = async () => {
    setError(null);

    const stored = Object.entries(localStorage)
      .filter(([key]) => key.startsWith('passkey:'));

    if (stored.length === 0) {
      setError('No passkey found. Create one first.');
      return;
    }

    const last = JSON.parse(stored[stored.length - 1][1]);
    onLogin(last.address as `0x${string}`);
  };

  if (available === null) {
    return <div className="text-sm opacity-50">Checking WebAuthn support...</div>;
  }

  if (!available) {
    return (
      <div className="text-sm text-red-500">
        Platform authenticator (FaceID / TouchID) is not available on this device.
      </div>
    );
  }

  if (userAddress) {
    return (
      <div className="flex flex-col items-center gap-2">
        <div className="text-sm font-mono bg-opacity-10 bg-ritual-500 px-3 py-1 rounded-lg">
          {userAddress.slice(0, 10)}...{userAddress.slice(-6)}
        </div>
        <button onClick={onLogout} className="text-xs text-red-400 hover:text-red-300 underline">
          Log out
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center gap-3">
      <button
        onClick={handleCreate}
        disabled={creating}
        className="bg-ritual-600 hover:bg-ritual-700 disabled:opacity-50 text-white font-medium px-6 py-2.5 rounded-xl transition-colors"
      >
        {creating ? 'Setting up...' : 'Create Passkey'}
      </button>
      <button
        onClick={handleLogin}
        className="text-sm text-ritual-400 hover:text-ritual-300 underline"
      >
        I already have a passkey
      </button>
      {error && <div className="text-sm text-red-400">{error}</div>}
    </div>
  );
}
