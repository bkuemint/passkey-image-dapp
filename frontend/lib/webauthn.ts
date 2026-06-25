import { keccak256, concat, toBytes, getAddress } from 'viem';

export function isPasskeySupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.PublicKeyCredential !== 'undefined' &&
    typeof window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable === 'function'
  );
}

export async function isPlatformAuthenticatorAvailable(): Promise<boolean> {
  if (!isPasskeySupported()) return false;
  return window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
}

function extractP256PublicKey(attestation: AuthenticatorAttestationResponse): Uint8Array {
  const publicKeyDer = new Uint8Array(attestation.getPublicKey()!);
  const uncompressed = publicKeyDer.slice(-65);
  if (uncompressed[0] !== 0x04) throw new Error('Expected uncompressed P-256 key');
  return uncompressed.slice(1);
}

export function passKeyToAddress(publicKeyX: Uint8Array, publicKeyY: Uint8Array): `0x${string}` {
  const hash = keccak256(concat([publicKeyX, publicKeyY]));
  return getAddress(`0x${hash.slice(26)}`);
}

export async function safeWebAuthnCall<T>(fn: () => Promise<T>): Promise<{ result: T } | { error: string; code: string }> {
  try {
    return { result: await fn() };
  } catch (err) {
    if (err instanceof DOMException) {
      switch (err.name) {
        case 'NotAllowedError':
          return { error: 'User cancelled the biometric prompt or timed out.', code: 'CANCELLED' };
        case 'SecurityError':
          return { error: 'WebAuthn blocked — the RP ID does not match the current domain.', code: 'WRONG_DOMAIN' };
        case 'InvalidStateError':
          return { error: 'A credential with this ID already exists on this authenticator.', code: 'DUPLICATE' };
        case 'NotSupportedError':
          return { error: 'This browser or device does not support the requested authenticator type.', code: 'UNSUPPORTED' };
        default:
          return { error: `WebAuthn error: ${err.name} — ${err.message}`, code: 'UNKNOWN' };
      }
    }
    return { error: String(err), code: 'UNKNOWN' };
  }
}

export async function createPasskey(username: string): Promise<{
  credentialId: string;
  publicKeyX: Uint8Array;
  publicKeyY: Uint8Array;
  address: `0x${string}`;
}> {
  const challenge = crypto.getRandomValues(new Uint8Array(32));

  const credential = await navigator.credentials.create({
    publicKey: {
      rp: { name: 'Passkey Image dApp', id: window.location.hostname },
      user: {
        id: new TextEncoder().encode(username),
        name: username,
        displayName: username,
      },
      challenge,
      pubKeyCredParams: [{ alg: -7, type: 'public-key' }],
      authenticatorSelection: {
        authenticatorAttachment: 'platform',
        residentKey: 'required',
        userVerification: 'required',
      },
      attestation: 'none',
    },
  }) as PublicKeyCredential;

  const attestation = credential.response as AuthenticatorAttestationResponse;
  const publicKeyBytes = extractP256PublicKey(attestation);
  const publicKeyX = publicKeyBytes.slice(0, 32);
  const publicKeyY = publicKeyBytes.slice(32, 64);
  const address = passKeyToAddress(publicKeyX, publicKeyY);

  return { credentialId: credential.id, publicKeyX, publicKeyY, address };
}

export async function authenticateWithPasskey(): Promise<{
  credentialId: string;
  address: `0x${string}`;
} | null> {
  const storedKeys = Object.entries(localStorage)
    .filter(([key]) => key.startsWith('passkey:'))
    .map(([key, val]) => ({ credentialId: key.replace('passkey:', ''), ...JSON.parse(val) }));

  if (storedKeys.length === 0) return null;

  const challenge = crypto.getRandomValues(new Uint8Array(32));

  const assertion = await navigator.credentials.get({
    publicKey: {
      challenge,
      userVerification: 'required',
    },
  }) as PublicKeyCredential;

  const stored = storedKeys.find(k => k.credentialId === assertion.id);
  if (!stored) return null;

  const address = passKeyToAddress(
    new Uint8Array(toBytes(stored.x)),
    new Uint8Array(toBytes(stored.y)),
  );

  return { credentialId: assertion.id, address };
}

export function getStoredPasskeyAddress(): `0x${string}` | null {
  const storedKeys = Object.entries(localStorage).filter(([key]) => key.startsWith('passkey:'));
  if (storedKeys.length === 0) return null;
  const { x, y } = JSON.parse(storedKeys[0][1]);
  return passKeyToAddress(new Uint8Array(toBytes(x)), new Uint8Array(toBytes(y)));
}
