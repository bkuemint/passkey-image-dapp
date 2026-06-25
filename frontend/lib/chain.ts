import { defineChain } from 'viem';

export const ritualChain = defineChain({
  id: 1979,
  name: 'Ritual Chain',
  nativeCurrency: { name: 'RITUAL', symbol: 'RITUAL', decimals: 18 },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_RPC_URL || 'https://rpc.ritualfoundation.org'],
      webSocket: [process.env.NEXT_PUBLIC_WS_URL || 'wss://rpc.ritualfoundation.org/ws'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Ritual Explorer',
      url: 'https://explorer.ritualfoundation.org',
    },
  },
});

export const ADDRESSES = {
  RITUAL_WALLET: '0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948' as const,
  ASYNC_DELIVERY: '0x5A16214fF555848411544b005f7Ac063742f39F6' as const,
  TEE_SERVICE_REGISTRY: '0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F' as const,
  SECP256R1: '0x0000000000000000000000000000000000000100' as const,
};

export const PRECOMPILES = {
  IMAGE_CALL: '0x0000000000000000000000000000000000000818' as const,
};
