'use client';

import { useState, useEffect, useCallback } from 'react';
import { usePasskeyImage } from '@/hooks/usePasskeyImage';

interface Props {
  jobId: `0x${string}`;
  prompt: string;
}

export default function ImageDisplay({ jobId, prompt }: Props) {
  const { pollRequest } = usePasskeyImage();
  const [uri, setUri] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [pollCount, setPollCount] = useState(0);

  const check = useCallback(async () => {
    const result = await pollRequest(jobId);
    if (!result) return false;

    if (result.fulfilled) {
      if (result.failed) {
        setError(result.errorMessage || 'Generation failed');
        setLoading(false);
      } else if (result.uri) {
        setUri(result.uri);
        setLoading(false);
      }
      return true;
    }
    return false;
  }, [jobId, pollRequest]);

  useEffect(() => {
    const interval = setInterval(async () => {
      setPollCount(c => c + 1);
      const done = await check();
      if (done) clearInterval(interval);
    }, 3000);

    return () => clearInterval(interval);
  }, [check]);

  useEffect(() => {
    check();
  }, [check]);

  return (
    <div className="w-full rounded-xl border border-ritual-700 overflow-hidden bg-black/20">
      <div className="p-3 border-b border-ritual-800 text-sm truncate" title={prompt}>
        {prompt}
      </div>
      <div className="flex items-center justify-center min-h-[200px]">
        {loading && (
          <div className="flex flex-col items-center gap-2 text-sm opacity-60">
            <div className="animate-pulse-soft">Generating...</div>
            <div className="text-xs">Polling for result ({pollCount})</div>
          </div>
        )}
        {error && (
          <div className="text-red-400 text-sm p-4">{error}</div>
        )}
        {uri && (
          <img
            src={convertStorageUri(uri)}
            alt={prompt}
            className="max-w-full h-auto"
          />
        )}
      </div>
    </div>
  );
}

function convertStorageUri(uri: string): string {
  if (uri.startsWith('gs://')) {
    return uri.replace('gs://', 'https://storage.googleapis.com/');
  }
  if (uri.startsWith('hf://')) {
    const path = uri.slice(5);
    const parts = path.split('/');
    if (parts.length >= 2) {
      const repo = parts.slice(0, 2).join('/');
      const filePath = parts.slice(2).join('/');
      return `https://huggingface.co/${repo}/resolve/main/${filePath}`;
    }
    return `https://huggingface.co/${path}`;
  }
  return uri;
}
