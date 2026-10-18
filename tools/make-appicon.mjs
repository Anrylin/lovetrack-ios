#!/usr/bin/env node
/**
 * 生成 App 图标（1024×1024 PNG，无第三方依赖）
 * 设计：粉紫渐变底 + 白色定位针 + 心形镂空
 *   node tools/make-appicon.mjs
 */
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SIZE = 1024;

/* ---------------- PNG 编码 ---------------- */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function encodePNG(width, height, rgba) {
  // 每行前加 filter type 0
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // color type RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/* ---------------- 图形数学 ---------------- */

const C = SIZE / 2;

// 渐变：左上 粉 → 右下 紫
const C1 = [255, 92, 155];
const C2 = [140, 92, 245];

function bgGradient(x, y) {
  const t = (x / SIZE * 0.55 + y / SIZE * 0.45);
  return [
    Math.round(C1[0] + (C2[0] - C1[0]) * t),
    Math.round(C1[1] + (C2[1] - C1[1]) * t),
    Math.round(C1[2] + (C2[2] - C1[2]) * t),
  ];
}

// 定位针：圆 + 三角（teardrop）
const PIN_CY = 430;
const PIN_R = 205;
const PIN_TIP_Y = 830;

function inPin(x, y) {
  const dx = x - C;
  const dy = y - PIN_CY;
  if (dx * dx + dy * dy <= PIN_R * PIN_R) return true;
  if (y >= PIN_CY && y <= PIN_TIP_Y) {
    const halfWidth = PIN_R * (PIN_TIP_Y - y) / (PIN_TIP_Y - PIN_CY);
    if (Math.abs(dx) <= halfWidth) return true;
  }
  return false;
}

// 心形（隐式方程）
function inHeart(x, y, scale) {
  const hx = (x - C) / scale;
  const hy = -(y - PIN_CY) / scale + 0.15;
  const a = hx * hx + hy * hy - 1;
  return a * a * a - hx * hx * hy * hy * hy <= 0;
}

/* ---------------- 绘制 ---------------- */

const rgba = Buffer.alloc(SIZE * SIZE * 4);
const HEART_SCALE = 105;

for (let y = 0; y < SIZE; y += 1) {
  for (let x = 0; x < SIZE; x += 1) {
    const i = (y * SIZE + x) * 4;
    const bg = bgGradient(x, y);

    let rgb = bg;
    if (inPin(x, y)) {
      // 针体白色；针孔（心形）回填背景色
      rgb = inHeart(x, y, HEART_SCALE) ? bg : [255, 255, 255];
    }

    rgba[i] = rgb[0];
    rgba[i + 1] = rgb[1];
    rgba[i + 2] = rgb[2];
    rgba[i + 3] = 255;
  }
}

/* ---------------- 落盘 ---------------- */

const outDir = join(ROOT, 'Assets.xcassets', 'AppIcon.appiconset');
mkdirSync(outDir, { recursive: true });

const png = encodePNG(SIZE, SIZE, rgba);
writeFileSync(join(outDir, 'icon-1024.png'), png);

const contents = {
  images: [
    {
      filename: 'icon-1024.png',
      idiom: 'universal',
      platform: 'ios',
      size: '1024x1024',
    },
  ],
  info: { author: 'xcode', version: 1 },
};
writeFileSync(join(outDir, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');

// Assets.xcassets 根 Contents.json
writeFileSync(
  join(ROOT, 'Assets.xcassets', 'Contents.json'),
  JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n',
);

console.log(`✅ ${join(outDir, 'icon-1024.png')}  (${(png.length / 1024).toFixed(1)} KB)`);
console.log(`✅ Assets.xcassets/Contents.json`);
console.log(`✅ AppIcon.appiconset/Contents.json`);
