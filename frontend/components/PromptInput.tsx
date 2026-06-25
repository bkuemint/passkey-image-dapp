'use client';

import { useState } from 'react';
import { usePasskeyImage } from '@/hooks/usePasskeyImage';

interface Props {
  userAddress: `0x${string}`;
  onRequest: (jobId: `0x${string}`, prompt: string) => void;
}

export default function PromptInput({ userAddress, onRequest }: Props) {
  const [prompt, setPrompt] = useState('');
  const { submitRequest, submitting } = usePasskeyImage();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!prompt.trim() || submitting) return;

    const result = await submitRequest(prompt.trim());
    if (result?.jobId) {
      onRequest(result.jobId, prompt.trim());
      setPrompt('');
    }
  };

  return (
    <form onSubmit={handleSubmit} className="w-full flex flex-col gap-3">
      <label htmlFor="prompt" className="text-sm font-medium">
        Describe the image you want to generate
      </label>
      <textarea
        id="prompt"
        value={prompt}
        onChange={e => setPrompt(e.target.value)}
        placeholder="A serene Japanese garden at sunset, digital art..."
        rows={3}
        className="w-full resize-none rounded-xl border border-ritual-700 bg-transparent p-3 text-sm focus:outline-none focus:ring-2 focus:ring-ritual-500"
      />
      <button
        type="submit"
        disabled={!prompt.trim() || submitting}
        className="self-end bg-ritual-600 hover:bg-ritual-700 disabled:opacity-40 text-white font-medium px-5 py-2 rounded-xl transition-colors"
      >
        {submitting ? 'Submitting...' : 'Generate'}
      </button>
    </form>
  );
}
