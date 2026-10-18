import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

const relayRoot = path.resolve(__dirname, '../..');

describe('diagnostic scripts', () => {
  it.each(['debug-api.js', 'debug-tools.js'])('starts %s with its ws dependency', script => {
    const result = spawnSync(process.execPath, [path.resolve(__dirname, '../../scripts/lib', script)], {
      encoding: 'utf8',
    });

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
  });

  it.each(['debug-integration.js', 'debug-diagnostic.js'])('starts %s and prints its help', script => {
    const result = spawnSync(process.execPath, [path.join(relayRoot, 'scripts/lib', script)], {
      encoding: 'utf8',
    });

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
  });

  it('points every package.json script at a file that exists', () => {
    const { scripts } = JSON.parse(readFileSync(path.join(relayRoot, 'package.json'), 'utf8')) as {
      scripts: Record<string, string>;
    };
    const targets = Object.values(scripts).flatMap(command =>
      [...command.matchAll(/\b(?:bun|node|bash)\s+(scripts\/\S+)/g)].map(match => match[1])
    );

    expect(targets.length).toBeGreaterThan(0);
    expect(targets.filter(target => !existsSync(path.join(relayRoot, target)))).toEqual([]);
  });
});
