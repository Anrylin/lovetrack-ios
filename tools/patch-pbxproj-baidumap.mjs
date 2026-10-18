#!/usr/bin/env node
/**
 * 给 project.pbxproj 接入百度地图 SDK（链接 + 桥接头 + 系统库）
 *
 *   node tools/patch-pbxproj-baidumap.mjs          # 写入
 *   node tools/patch-pbxproj-baidumap.mjs --check  # 只检查
 *
 * 前置：Frameworks/ 下已放好 BaiduMapAPI_Base/Map/Utils.framework 与 libzstd_iphoneos_arm64.a
 * （由 CI 从 GitHub Release 下载；本地构建时也需手动放置）
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PBX = join(ROOT, 'LoveTrack.xcodeproj', 'project.pbxproj');
const CHECK_ONLY = process.argv.includes('--check');

let src = readFileSync(PBX, 'utf8');
const log = [];

if (src.includes('BaiduMapAPI_Map.framework /* BaiduMapAPI_Map */')) {
  console.log('⏭  已接入百度地图，跳过');
  process.exit(0);
}

/* ---------- 待接入的二进制 ---------- */

// 3 个 framework + 1 个静态库
const FRAMEWORKS = [
  { id: 'BA1D0000000000000000001', name: 'BaiduMapAPI_Base.framework', isStatic: false },
  { id: 'BA1D0000000000000000002', name: 'BaiduMapAPI_Map.framework', isStatic: false },
  { id: 'BA1D0000000000000000003', name: 'BaiduMapAPI_Utils.framework', isStatic: false },
  { id: 'BA1D0000000000000000004', name: 'libzstd_iphoneos_arm64.a', isStatic: true },
];

// 需要显式链接的系统库（百度官方要求）
const SYS_LIBS = [
  { id: 'BA1D000000000000000000A1', name: 'libsqlite3.tbd', type: 'sourcecode.text-based-dylib-definition' },
  { id: 'BA1D000000000000000000A2', name: 'libz.tbd', type: 'sourcecode.text-based-dylib-definition' },
  { id: 'BA1D000000000000000000A3', name: 'libc++.tbd', type: 'sourcecode.text-based-dylib-definition' },
  { id: 'BA1D000000000000000000A4', name: 'SystemConfiguration.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000A5', name: 'CoreTelephony.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000A6', name: 'QuartzCore.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000A7', name: 'OpenGLES.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000A8', name: 'CoreText.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000A9', name: 'Security.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000B1', name: 'CoreGraphics.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000B2', name: 'AVFoundation.framework', type: 'wrapper.framework' },
  { id: 'BA1D000000000000000000B3', name: 'CoreMotion.framework', type: 'wrapper.framework' },
];

function buildFileId(prefix, i) {
  return `BA1DBF00000000000000${String(i).padStart(4, '0')}`;
}

/* ---------- 1. PBXBuildFile ---------- */
let buildFiles = '';
let fileRefs = '';
let phaseFiles = '';

let idx = 0;
for (const fw of FRAMEWORKS) {
  idx += 1;
  const bf = buildFileId('', idx);
  buildFiles += `\t\t${bf} /* ${fw.name} in Frameworks */ = {isa = PBXBuildFile; fileRef = ${fw.id} /* ${fw.name} */; };\n`;
  phaseFiles += `\t\t\t\t${bf} /* ${fw.name} in Frameworks */,\n`;
  fileRefs += `\t\t${fw.id} /* ${fw.name} */ = {isa = PBXFileReference; lastKnownFileType = ${
    fw.isStatic ? '"archive.ar"' : 'wrapper.framework'
  }; name = ${fw.name}; path = Frameworks/${fw.name}; sourceTree = SOURCE_ROOT; };\n`;
}

let sysIdx = 100;
for (const lib of SYS_LIBS) {
  sysIdx += 1;
  const bf = buildFileId('', sysIdx);
  buildFiles += `\t\t${bf} /* ${lib.name} in Frameworks */ = {isa = PBXBuildFile; fileRef = ${lib.id} /* ${lib.name} */; };\n`;
  phaseFiles += `\t\t\t\t${bf} /* ${lib.name} in Frameworks */,\n`;
  fileRefs += `\t\t${lib.id} /* ${lib.name} */ = {isa = PBXFileReference; lastKnownFileType = ${lib.type}; name = ${lib.name}; path = ${lib.name}; sourceTree = SDKROOT; };\n`;
}

/* 插入 PBXBuildFile 段 */
if (!src.includes('/* End PBXBuildFile section */')) {
  console.error('❌ 找不到 PBXBuildFile 段');
  process.exit(1);
}
src = src.replace(
  '/* End PBXBuildFile section */',
  buildFiles + '/* End PBXBuildFile section */',
);
log.push(`✅ PBXBuildFile +${FRAMEWORKS.length + SYS_LIBS.length}`);

/* 插入 PBXFileReference 段 */
if (!src.includes('/* End PBXFileReference section */')) {
  console.error('❌ 找不到 PBXFileReference 段');
  process.exit(1);
}
src = src.replace(
  '/* End PBXFileReference section */',
  fileRefs + '/* End PBXFileReference section */',
);
log.push(`✅ PBXFileReference +${FRAMEWORKS.length + SYS_LIBS.length}`);

/* 追加到 Frameworks build phase 的 files 列表 */
const phaseAnchor = '\t\t\t\t0998FA1105FCF42B22AD9A07 /* CoreLocation.framework in Frameworks */,\n';
if (!src.includes(phaseAnchor)) {
  console.error('❌ 找不到 Frameworks phase 的 CoreLocation 条目');
  process.exit(1);
}
src = src.replace(phaseAnchor, phaseAnchor + phaseFiles);
log.push('✅ Frameworks 链接项已追加');

/* 设置桥接头：两个 configuration 都要 */
const bridgeCount = (src.match(/SWIFT_OBJC_BRIDGING_HEADER/g) || []).length;
if (bridgeCount === 0) {
  // 插到每个 buildSettings 块里的 PRODUCT_BUNDLE_IDENTIFIER 之后
  src = src.replace(
    /PRODUCT_BUNDLE_IDENTIFIER = com\.lovetrack\.app;/g,
    'PRODUCT_BUNDLE_IDENTIFIER = com.lovetrack.app;\n\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "LoveTrack-Bridging-Header.h";',
  );
  log.push('✅ SWIFT_OBJC_BRIDGING_HEADER 已设置');
} else {
  log.push(`⏭  桥接头已存在（${bridgeCount} 处）`);
}

/* 允许非模块化头文件（百度 SDK 是 ObjC，避免 module 报错） */
if (!src.includes('CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES')) {
  src = src.replace(
    /PRODUCT_BUNDLE_IDENTIFIER = com\.lovetrack\.app;/g,
    'PRODUCT_BUNDLE_IDENTIFIER = com.lovetrack.app;\n\t\t\t\tCLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES;',
  );
  log.push('✅ 允许非模块化 include');
}

console.log(log.join('\n'));

/* 自检 */
const checks = [
  ['BaiduMapAPI_Map 引用', 'BaiduMapAPI_Map.framework'],
  ['libzstd 静态库', 'libzstd_iphoneos_arm64.a'],
  ['libsqlite3 链接', 'libsqlite3.tbd in Frameworks'],
  ['桥接头设置', 'SWIFT_OBJC_BRIDGING_HEADER'],
];
console.log('\n自检：');
let ok = true;
for (const [n, needle] of checks) {
  const hit = src.includes(needle);
  if (!hit) ok = false;
  console.log(`  ${hit ? '✅' : '❌'} ${n}`);
}
if (!ok) {
  console.error('\n自检未通过，未写入');
  process.exit(1);
}

if (CHECK_ONLY) {
  console.log('\n（--check 模式，未写入）');
} else {
  writeFileSync(PBX, src, 'utf8');
  console.log('\n✅ 已写入 project.pbxproj');
}
