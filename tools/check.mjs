// public/index.html 안의 인라인 스크립트를 꺼내 문법 검사
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const html = readFileSync('public/index.html', 'utf8');
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);
if (!blocks.length) { console.error('인라인 스크립트가 없습니다'); process.exit(1); }
const dir = mkdtempSync(join(tmpdir(), 'chk-'));
blocks.forEach((js, i) => {
  const f = join(dir, `s${i}.js`); writeFileSync(f, js);
  execFileSync(process.execPath, ['--check', f], { stdio: 'inherit' });
});
console.log(`ok: 스크립트 ${blocks.length}개`);
