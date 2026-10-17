#!/usr/bin/env node
/**
 * 解析编译产物里的 Info.plist（二进制 plist），确认关键字段。
 *   node tools/inspect-ipa.mjs dist/LoveTrack-unsigned.ipa
 */
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

// bplist-parser 是 CommonJS，用 createRequire 互操作
const require = createRequire(import.meta.url);
const bplistParser = require('bplist-parser');

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ipaPath = resolve(ROOT, process.argv[2] ?? 'dist/LoveTrack-unsigned.ipa');

if (!statSync(ipaPath).isFile()) {
  console.error('找不到 ipa:', ipaPath);
  process.exit(1);
}

const work = mkdtempSync(join(tmpdir(), 'ipa-inspect-'));
try {
  execFileSync('tar', ['-xf', ipaPath, '-C', work], { stdio: 'ignore' });
  const appDir = join(work, 'Payload', 'LoveTrack.app');
  const infoPath = join(appDir, 'Info.plist');

  const [plist] = bplistParser.parseBuffer(readFileSync(infoPath));
  const show = (k) => {
    const v = plist[k];
    if (v === undefined) return '—';
    return Array.isArray(v) ? JSON.stringify(v) : String(v);
  };

  console.log(`\nipa: ${ipaPath}`);
  console.log(`大小: ${(statSync(ipaPath).size / 1024).toFixed(1)} KB\n`);

  const rows = [
    ['CFBundleIdentifier', show('CFBundleIdentifier')],
    ['CFBundleName', show('CFBundleName')],
    ['CFBundleDisplayName', show('CFBundleDisplayName')],
    ['CFBundleShortVersionString', show('CFBundleShortVersionString')],
    ['CFBundleVersion', show('CFBundleVersion')],
    ['MinimumOSVersion', show('MinimumOSVersion')],
    ['UIDeviceFamily / 目标机型', show('UIDeviceFamily')],
    ['UIBackgroundModes', show('UIBackgroundModes')],
    ['NSLocationWhenInUseUsageDescription', show('NSLocationWhenInUseUsageDescription').slice(0, 40) + '…'],
    ['NSLocationAlwaysAndWhenInUse…', show('NSLocationAlwaysAndWhenInUseUsageDescription').slice(0, 40) + '…'],
    ['NSAppTransportSecurity', JSON.stringify(plist.NSAppTransportSecurity ?? {})],
    ['UISupportedInterfaceOrientations', show('UISupportedInterfaceOrientations')],
  ];
  for (const [k, v] of rows) {
    console.log(`  ${k.padEnd(38, ' ')} ${v}`);
  }

  // 结构检查
  const files = readdirSync(appDir);
  const hasSig = files.includes('_CodeSignature');
  const execName = plist.CFBundleExecutable;
  console.log(`\n  可执行文件 (${execName}) : ${files.includes(execName) ? '✅ 存在' : '❌ 缺失'}`);
  console.log(`  代码签名目录            : ${hasSig ? '⚠️ 有 _CodeSignature（意外，本应是未签名）' : '✅ 未签名（符合预期，需自签）'}`);

  const frameworks = files.filter((f) => f.endsWith('.framework') || f.endsWith('.dylib'));
  console.log(`  内嵌框架                : ${frameworks.length ? frameworks.join(', ') : '无（纯系统框架）'}`);

  console.log(`\n  最低系统要求: iOS ${plist.MinimumOSVersion ?? '?'}`);
  const major = Number(String(plist.MinimumOSVersion ?? '0').split('.')[0]);
  if (major < 17) {
    console.log(`  ⚠️  注意：工程用了 iOS 17 才有的 Map(position:) API，但 plist 声明最低 iOS ${plist.MinimumOSVersion}`);
    console.log(`      在 iOS ${major}.x 设备上运行可能崩溃，请用 iOS 17+ 的设备测试`);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
