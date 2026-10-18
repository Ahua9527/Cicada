import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

import {
  COMMAND_PROTOCOL_VERSION,
  COMMANDS,
} from '../packages/shared/dist/protocol/commands.js';
import { COMMAND_DESCRIPTIONS } from '../packages/shared/dist/constants/commands.js';

const commandsURL = new URL('../packages/shared/COMMANDS.md', import.meta.url);
const startMarker = '<!-- commands:begin -->';
const endMarker = '<!-- commands:end -->';
const commandsDoc = await readFile(commandsURL, 'utf8');
const start = commandsDoc.indexOf(startMarker);
const end = commandsDoc.indexOf(endMarker);
if (start === -1 || end === -1 || end < start) {
  throw new Error('COMMANDS.md must contain ordered commands:begin and commands:end markers');
}
const table = [
  startMarker,
  '<!-- 自动生成，改命令后运行 bun run protocol:generate -->',
  '| Command | Description |',
  '|---|---|',
  ...COMMANDS.map((command) => `| \`${command}\` | ${COMMAND_DESCRIPTIONS[command]} |`),
  endMarker,
].join('\n');

const outputURL = new URL('../packages/shared/protocol/command-contract.json', import.meta.url);
const contract = {
  protocol_version: COMMAND_PROTOCOL_VERSION,
  commands: COMMANDS,
};

await mkdir(fileURLToPath(new URL('.', outputURL)), { recursive: true });
await writeFile(outputURL, `${JSON.stringify(contract, null, 2)}\n`, 'utf8');
await writeFile(
  commandsURL,
  commandsDoc.slice(0, start) + table + commandsDoc.slice(end + endMarker.length),
  'utf8',
);
