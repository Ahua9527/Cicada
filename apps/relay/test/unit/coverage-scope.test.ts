import { readdirSync } from 'node:fs';
import path from 'node:path';

// bun test 只统计被加载过的文件：这里加载覆盖率统计范围内的全部源码（对应原 Jest 的 collectCoverageFrom），
// 没有任何测试的文件也会计入覆盖率，不会让门槛假通过。
const roots = [
  path.resolve(__dirname, '../../src'),
  path.resolve(__dirname, '../../../../packages/shared/src/validators'),
];

const sourceFiles = roots.flatMap(root =>
  readdirSync(root, { recursive: true, encoding: 'utf8' })
    .filter(file => file.endsWith('.ts') && !file.endsWith('.d.ts'))
    .map(file => path.join(root, file))
);

describe('coverage scope', () => {
  it('loads every source file in the coverage scope', async () => {
    expect(sourceFiles.length).toBeGreaterThan(0);
    for (const file of sourceFiles) {
      await expect(import(file)).resolves.toBeDefined();
    }
  });
});
