#!/usr/bin/env node
/**
 * 下载 GitHub Actions 产物并校验 ipa 结构。
 *   node tools/download-artifact.mjs owner/repo <artifact_id> [输出目录]
 */
import { mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = resolve(ROOT, 'dist');
const TOKEN = process.env.GITHUB_TOKEN;
const [repo, artifactId, outArg] = process.argv.slice(2);

if (!TOKEN || !repo || !artifactId) {
  console.error('用法: GITHUB_TOKEN=xxx node tools/download-artifact.mjs owner/repo <artifact_id>');
  process.exit(1);
}

const target = outArg ? resolve(outArg) : OUT;
mkdirSync(target, { recursive: true });

console.log(`下载 ${repo} 的产物 ${artifactId} …`);

const res = await fetch(`https://api.github.com/repos/${repo}/actions/artifacts/${artifactId}/zip`, {
  headers: {
    Authorization: `Bearer ${TOKEN}`,
    Accept: 'application/vnd.github+json',
    'User-Agent': 'lovetrack-download',
  },
  redirect: 'manual',
});

let buf;
if (res.status >= 300 && res.status < 400) {
  const loc = res.headers.get('location');
  if (!loc) {
    console.error('重定向没有 Location');
    process.exit(1);
  }
  console.log('  跟随重定向下载…');
  const fileRes = await fetch(loc);
  if (!fileRes.ok) {
    console.error(`  下载失败 ${fileRes.status}`);
    process.exit(1);
  }
  buf = Buffer.from(await fileRes.arrayBuffer());
} else if (res.ok) {
  buf = Buffer.from(await res.arrayBuffer());
} else {
  console.error(`  ❌ ${res.status}: ${await res.text()}`);
  process.exit(1);
}

const zipPath = join(target, `${artifactId}.zip`);
writeFileSync(zipPath, buf);
console.log(`  ✅ ${(buf.length / 1024).toFixed(1)} KB → ${zipPath}`);

// 解压（zip 内是 ipa 文件）
const extractDir = join(target, `${artifactId}-extracted`);
rmSync(extractDir, { recursive: true, force: true });
mkdirSync(extractDir, { recursive: true });
execFileSync('tar', ['-xf', zipPath, '-C', extractDir], { stdio: 'inherit' });

const found = readdirSync(extractDir);
console.log(`  解压得到: ${found.join(', ')}`);

const ipaName = found.find((f) => f.endsWith('.ipa'));
if (!ipaName) {
  console.error('  ❌ 没找到 .ipa');
  process.exit(1);
}
const ipaPath = join(extractDir, ipaName);
const finalPath = join(target, ipaName);
writeFileSync(finalPath, readFileSync(ipaPath));
console.log(`  ✅ ipa: ${finalPath}  (${(statSync(finalPath).size / 1024).toFixed(1)} KB)`);

/* ------------------------------ 校验 ipa 结构 ------------------------------ */
console.log('\n校验 ipa：');
const checkDir = join(target, '_ipa_check');
rmSync(checkDir, { recursive: true, force: true });
mkdirSync(checkDir, { recursive: true });
execFileSync('tar', ['-xf', finalPath, '-C', checkDir], { stdio: 'ignore' });

const appDir = join(checkDir, 'Payload', 'LoveTrack.app');
const infoPath = join(appDir, 'Info.plist');

if (!statSync(appDir).isDirectory()) {
  console.error('  ❌ 缺 Payload/LoveTrack.app');
  process.exit(1);
}
console.log('  ✅ Payload/LoveTrack.app 存在');

const plist = readFileSync(infoPath, 'utf8');
const pick = (key) => {
  const m = plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`));
  return m ? m[1] : null;
};
console.log(`  CFBundleIdentifier      : ${pick('CFBundleIdentifier')}`);
console.log(`  CFBundleShortVersion    : ${pick('CFBundleShortVersionString')}`);
console.log(`  MinimumOSVersion        : ${pick('MinimumOSVersion')}`);

const hasBgModes = plist.includes('UIBackgroundModes');
console.log(`  后台模式(location)      : ${hasBgModes ? '✅ 有' : '❌ 无'}`);

const hasSig = readdirSync(appDir).includes('_CodeSignature');
console.log(`  代码签名                : ${hasSig ? '有签名' : '⚠️ 未签名（需自签后才能装）'}`);

const exec = readdirSync(appDir).find((f) => f === 'LoveTrack');
console.log(`  可执行文件              : ${exec ? '✅ LoveTrack' : '❌ 缺失'}`);

rmSync(checkDir, { recursive: true, force: true });
console.log(`\n完成：${finalPath}`);
