import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import {
  COMMAND_PROTOCOL_VERSION,
  COMMANDS,
} from '../packages/shared/dist/protocol/commands.js';

const outputURL = new URL('../packages/shared/protocol/command-contract.json', import.meta.url);
const contract = {
  protocol_version: COMMAND_PROTOCOL_VERSION,
  commands: COMMANDS,
};

await mkdir(fileURLToPath(new URL('.', outputURL)), { recursive: true });
await writeFile(outputURL, `${JSON.stringify(contract, null, 2)}\n`, 'utf8');
