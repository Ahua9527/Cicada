import { spawnSync } from 'node:child_process';
import path from 'node:path';

describe('diagnostic scripts', () => {
  it.each(['debug-api.js', 'debug-tools.js'])('starts %s with its ws dependency', script => {
    const result = spawnSync(process.execPath, [path.resolve(__dirname, '../../scripts/lib', script)], {
      encoding: 'utf8',
    });

    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
  });
});
