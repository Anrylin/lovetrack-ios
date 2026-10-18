#!/usr/bin/env node
/**
 * 回滚百度地图接入，把工程恢复到可构建状态
 *   node tools/rollback-baidumap.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const log = [];

/* ---------- 1. pbxproj ---------- */
const PBX = join(ROOT, 'LoveTrack.xcodeproj', 'project.pbxproj');
let p = readFileSync(PBX, 'utf8');
const before = p.length;

// 删掉所有 BA1D 开头的行（PBXBuildFile / PBXFileReference / phase 条目）
p = p
  .split('\n')
  .filter((line) => !/^\s*BA1D[0-9A-F]{20,}/.test(line))
  .join('\n');

// 删掉桥接头 / 搜索路径 / 非模块化 include 设置
p = p
  .split('\n')
  .filter((line) => {
    const t = line.trim();
    return !(
      t.startsWith('SWIFT_OBJC_BRIDGING_HEADER =') ||
      t.startsWith('FRAMEWORK_SEARCH_PATHS =') ||
      t.startsWith('LIBRARY_SEARCH_PATHS =') ||
      t.startsWith('CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES =')
    );
  })
  .join('\n');

writeFileSync(PBX, p, 'utf8');
log.push(`✅ pbxproj 清理：${before} → ${p.length} 字节`);

/* ---------- 2. MapKitView.swift：删掉百度代码段 ---------- */
const MK = join(ROOT, 'Map', 'MapKitView.swift');
let mk = readFileSync(MK, 'utf8');
const marker = '// MARK: - 百度地图（BMKMapView 封装）';
const idx = mk.indexOf(marker);
if (idx >= 0) {
  mk = mk.slice(0, idx).replace(/\s+$/, '') + '\n';
  writeFileSync(MK, mk, 'utf8');
  log.push('✅ MapKitView.swift 已移除百度地图代码');
} else {
  log.push('⏭  MapKitView.swift 无需清理');
}

/* ---------- 3. LoveTrackApp.swift：删初始化调用 ---------- */
const APP = join(ROOT, 'App', 'LoveTrackApp.swift');
let app = readFileSync(APP, 'utf8');
const appBefore = app.length;
app = app
  .split('\n')
  .filter((line) => {
    const t = line.trim();
    return !t.startsWith('BaiduMapManager.shared.start()') &&
      !t.includes('百度地图：BMKMapView 使用前必须初始化');
  })
  .join('\n');
if (app.length !== appBefore) {
  writeFileSync(APP, app, 'utf8');
  log.push('✅ LoveTrackApp.swift 已移除百度地图初始化');
} else {
  log.push('⏭  LoveTrackApp.swift 无需清理');
}

/* ---------- 4. AppTabView.swift：删掉百度地图卡片 ---------- */
const TAB = join(ROOT, 'App', 'AppTabView.swift');
let tab = readFileSync(TAB, 'utf8');
const tabBefore = tab.length;

// 移除调用
tab = tab.replace(/\n\s*baiduMapCard/g, '');
// 移除定义块（从 MARK 到 notPairedHint 之前）
const tabMarker = '    // MARK: 百度地图验证区块';
const ti = tab.indexOf(tabMarker);
if (ti >= 0) {
  const endMarker = '    private var notPairedHint: some View {';
  const ei = tab.indexOf(endMarker, ti);
  if (ei > ti) {
    tab = tab.slice(0, ti) + tab.slice(ei);
  }
}
if (tab.length !== tabBefore) {
  writeFileSync(TAB, tab, 'utf8');
  log.push('✅ AppTabView.swift 已移除百度地图卡片');
} else {
  log.push('⏭  AppTabView.swift 无需清理');
}

console.log(log.join('\n'));

/* ---------- 自检 ---------- */
const checks = [
  ['pbxproj 无 BA1D 残留', !readFileSync(PBX, 'utf8').match(/BA1D[0-9A-F]{20,}/)],
  ['无 bridging header 设置', !readFileSync(PBX, 'utf8').includes('SWIFT_OBJC_BRIDGING_HEADER')],
  ['MapKitView 无百度代码', !readFileSync(MK, 'utf8').includes('BMKMapView')],
  ['App 无百度初始化', !readFileSync(APP, 'utf8').includes('BaiduMapManager')],
  ['统计页无百度卡片', !readFileSync(TAB, 'utf8').includes('baiduMapCard')],
];
console.log('\n自检：');
let ok = true;
for (const [n, pass] of checks) {
  if (!pass) ok = false;
  console.log(`  ${pass ? '✅' : '❌'} ${n}`);
}
process.exit(ok ? 0 : 1);
