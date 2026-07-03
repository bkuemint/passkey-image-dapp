const { encrypt, ECIES_CONFIG } = require('eciesjs');

ECIES_CONFIG.symmetricNonceLength = 12;

const publicKeyHex = process.argv[2];
const secretsJson = process.argv[3] || '{"LLM_PROVIDER":"ritual"}';

const encrypted = encrypt(publicKeyHex, Buffer.from(secretsJson));
process.stdout.write(Buffer.from(encrypted));
