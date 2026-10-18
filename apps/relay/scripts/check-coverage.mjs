// bun test 的 coverageThreshold 按单个文件判定；这里按全部文件合计判定，与原 Jest 的 global 门槛一致。
// 用法（在 apps/relay 下）：bun scripts/check-coverage.mjs <最低比例>，读取 bun test --coverage 生成的 coverage/lcov.info
import { readFileSync } from 'node:fs';

const min = Number(process.argv[2]);
const totals = { LF: 0, LH: 0, FNF: 0, FNH: 0 };
for (const line of readFileSync('coverage/lcov.info', 'utf8').split('\n')) {
  const [key, value] = line.split(':');
  if (key in totals) {
    totals[key] += Number(value);
  }
}

const lines = totals.LH / totals.LF;
const functions = totals.FNH / totals.FNF;
console.log(
  `coverage: lines ${(lines * 100).toFixed(2)}%, functions ${(functions * 100).toFixed(2)}% (min ${min * 100}%)`
);
if (!(min > 0 && lines >= min && functions >= min)) {
  console.error('coverage below threshold');
  process.exit(1);
}
