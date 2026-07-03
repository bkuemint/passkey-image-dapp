const { encrypt, ECIES_CONFIG } = require('eciesjs');
const fs = require('fs');

ECIES_CONFIG.symmetricNonceLength = 12;

const publicKeyHex = process.argv[2];
const secretsJson = process.argv[3] || '{"LLM_PROVIDER":"ritual"}';
const outputPath = process.argv[4] || 'script/encrypted-secret.hex';

const encrypted = encrypt(publicKeyHex, Buffer.from(secretsJson));
const hex = '0x' + Buffer.from(encrypted).toString('hex');
fs.writeFileSync(outputPath, hex);
console.log('Encrypted secrets written to', outputPath);
