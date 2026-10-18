#!/usr/bin/env node
/**
 * 给 project.pbxproj 注入 Assets.xcassets，并补建 PBXResourcesBuildPhase。
 * 该工程由 XcodeGen 精简生成，原本没有任何资源打包阶段。
 *
 *   node tools/patch-pbxproj-assets.mjs          # 写入
 *   node tools/patch-pbxproj-assets.mjs --check  # 只检查
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PBX = join(ROOT, 'LoveTrack.xcodeproj', 'project.pbxproj');
const CHECK_ONLY = process.argv.includes('--check');

// 固定 UUID（24 位十六进制），便于重复执行识别
const BF = 'A1B2C3D4E5F6000000000001'; // Assets.xcassets in Resources
const FR = 'A1B2C3D4E5F6000000000002'; // file reference
const RP = 'A1B2C3D4E5F6000000000003'; // Resources build phase

let src = readFileSync(PBX, 'utf8');
const log = [];

if (src.includes(`${FR} /* Assets.xcassets */`)) {
  console.log('⏭  已注入过 Assets.xcassets，跳过');
  process.exit(0);
}

function must(name, anchor) {
  if (!src.includes(anchor)) {
    console.error(`❌ 锚点缺失：${name} → ${JSON.stringify(anchor)}`);
    process.exit(1);
  }
}

/* 1. PBXBuildFile */
must('PBXBuildFile', '/* End PBXBuildFile section */');
src = src.replace(
  '/* End PBXBuildFile section */',
  `\t\t${BF} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${FR} /* Assets.xcassets */; };\n/* End PBXBuildFile section */`,
);
log.push('✅ PBXBuildFile');

/* 2. PBXFileReference */
must('PBXFileReference', '/* End PBXFileReference section */');
src = src.replace(
  '/* End PBXFileReference section */',
  `\t\t${FR} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };\n/* End PBXFileReference section */`,
);
log.push('✅ PBXFileReference');

/* 3. 组成员（挂到 LoveTrack 组，和 Secrets.xcconfig 同级） */
const groupAnchor = '"TEMP_A0403576-3D25-43A9-8E74-2750EDE87089" /* Secrets.xcconfig */,';
must('PBXGroup children', groupAnchor);
src = src.replace(
  groupAnchor,
  `${groupAnchor}\n\t\t\t\t${FR} /* Assets.xcassets */,`,
);
log.push('✅ 组成员');

/* 4. target 的 buildPhases 引用 Resources */
const phaseAnchor = '9D1426791D24E9CCCE666C20 /* Frameworks */,';
must('buildPhases', phaseAnchor);
src = src.replace(
  phaseAnchor,
  `${phaseAnchor}\n\t\t\t\t${RP} /* Resources */,`,
);
log.push('✅ buildPhases');

/* 5. 新建 PBXResourcesBuildPhase section（紧跟 Sources section 之后） */
must('Sources section end', '/* End PBXSourcesBuildPhase section */');
src = src.replace(
  '/* End PBXSourcesBuildPhase section */',
  '/* End PBXSourcesBuildPhase section */\n' +
    '\n' +
    '/* Begin PBXResourcesBuildPhase section */\n' +
    `\t\t${RP} /* Resources */ = {\n` +
    '\t\t\tisa = PBXResourcesBuildPhase;\n' +
    '\t\t\tbuildActionMask = 2147483647;\n' +
    '\t\t\tfiles = (\n' +
    `\t\t\t\t${BF} /* Assets.xcassets in Resources */,\n` +
    '\t\t\t);\n' +
    '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n' +
    '\t\t};\n' +
    '/* End PBXResourcesBuildPhase section */',
);
log.push('✅ PBXResourcesBuildPhase');

console.log(log.join('\n'));

/* 自检 */
const checks = [
  ['BuildFile 条目', `${BF} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile`],
  ['FileReference 条目', `${FR} /* Assets.xcassets */ = {isa = PBXFileReference`],
  ['组成员', `${FR} /* Assets.xcassets */,`],
  ['buildPhases 引用', `${RP} /* Resources */,`],
  ['Resources section', `/* Begin PBXResourcesBuildPhase section */`],
];
console.log('\n自检：');
let ok = true;
for (const [name, needle] of checks) {
  const hit = src.includes(needle);
  if (!hit) ok = false;
  console.log(`  ${hit ? '✅' : '❌'} ${name}`);
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
