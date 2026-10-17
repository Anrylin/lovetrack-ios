#!/usr/bin/env node
/**
 * 用 Node 修改工程文件（UTF-8 安全，不会像 PowerShell 那样把中文读成乱码）
 *   node tools/patch-project.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function patch(relPath, replacements) {
  const file = join(ROOT, relPath);
  const before = readFileSync(file, 'utf8');
  let after = before;
  const applied = [];

  for (const { find, replace, expect = 1 } of replacements) {
    const count = after.split(find).length - 1;
    if (count !== expect) {
      console.error(`  ⚠️  ${relPath}: 期望匹配 ${expect} 处，实际 ${count} 处 → ${find.slice(0, 60)}`);
      if (count === 0) continue;
    }
    after = after.split(find).join(replace);
    applied.push({ find, count });
  }

  if (after !== before) {
    writeFileSync(file, after, 'utf8');
  }

  const lineCount = after.split('\n').length;
  console.log(`  ✅ ${relPath}  (${lineCount} 行, ${applied.length} 处替换)`);
  for (const a of applied) {
    console.log(`       ${a.count}× ${a.find.slice(0, 55).replace(/\n/g, '\\n')}`);
  }
  return after;
}

console.log('修补 iOS 工程：\n');

// 1. 后端地址指向已部署的服务
patch('Network/BackendConfig.swift', [
  {
    find: 'private static let defaultBackendURL = "http://YOUR_SERVER_IP:3000"',
    replace: 'private static let defaultBackendURL = "https://api.jiaqiya.xyz"',
  },
]);

// 2. 去掉作者的签名 Team ID（CI 用无签名编译，本地开工程时填自己的）
patch('LoveTrack.xcodeproj/project.pbxproj', [
  {
    find: 'DEVELOPMENT_TEAM = 2CG772X26Z;',
    replace: 'DEVELOPMENT_TEAM = "";',
    expect: 2,
  },
  {
    // TargetAttributes 里的小写形式
    find: 'DevelopmentTeam = 2CG772X26Z;',
    replace: 'DevelopmentTeam = "";',
    expect: 1,
  },
]);

// 3. 校验：中文注释是否还好
const bc = readFileSync(join(ROOT, 'Network/BackendConfig.swift'), 'utf8');
const hasChinese = bc.includes('后端配置');
const urlOk = bc.includes('defaultBackendURL = "https://api.jiaqiya.xyz"');
console.log('\n校验：');
console.log(`  中文注释完整    : ${hasChinese ? '✅' : '❌ 被破坏了'}`);
console.log(`  后端地址已替换  : ${urlOk ? '✅' : '❌'}`);

const pbx = readFileSync(join(ROOT, 'LoveTrack.xcodeproj/project.pbxproj'), 'utf8');
console.log(`  残留旧 Team ID  : ${pbx.includes('2CG772X26Z') ? '❌ 仍有' : '✅ 已清除'}`);
