import { NextRequest, NextResponse } from 'next/server';
import { createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { ritualChain } from '@/lib/chain';
import { consumerAbi } from '@/lib/contract';

const CONSUMER_ADDRESS = (process.env.NEXT_PUBLIC_CONSUMER_ADDRESS || '') as `0x${string}`;
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}` | undefined;

const ALLOWED_FUNCTIONS = new Set(['scheduleAutomaticImage', 'cancelAutomaticSchedule', 'setScheduleBasePrompt']);

function coerceArgs(functionName: string, args: unknown[]): unknown[] {
  const fn = consumerAbi.find(
    (entry): entry is typeof entry & { type: 'function'; inputs: { type: string }[] } =>
      entry.type === 'function' && entry.name === functionName
  );
  if (!fn || fn.type !== 'function') return args;

  return fn.inputs.map((input, i) => {
    const val = args[i];
    if ((input.type.startsWith('uint') || input.type.startsWith('int')) && typeof val === 'string') {
      return BigInt(val);
    }
    return val;
  });
}

export async function GET() {
  if (!PRIVATE_KEY) {
    return NextResponse.json({ error: 'PRIVATE_KEY not configured' }, { status: 500 });
  }
  const account = privateKeyToAccount(PRIVATE_KEY);
  return NextResponse.json({ signer: account.address });
}

export async function POST(req: NextRequest) {
  if (!PRIVATE_KEY) {
    return NextResponse.json({ error: 'PRIVATE_KEY not configured on server' }, { status: 500 });
  }

  try {
    const { functionName, args } = await req.json();

    if (!ALLOWED_FUNCTIONS.has(functionName)) {
      return NextResponse.json({ error: `Function '${functionName}' is not allowed` }, { status: 403 });
    }

    const account = privateKeyToAccount(PRIVATE_KEY);
    const walletClient = createWalletClient({ account, chain: ritualChain, transport: http() });
    const coerced = coerceArgs(functionName, args || []);

    const hash = await (walletClient.writeContract as any)({
      account,
      address: CONSUMER_ADDRESS,
      abi: consumerAbi,
      functionName,
      args: coerced,
    });

    return NextResponse.json({ hash });
  } catch (err) {
    console.error('API owner-action error:', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : String(err) },
      { status: 500 }
    );
  }
}
