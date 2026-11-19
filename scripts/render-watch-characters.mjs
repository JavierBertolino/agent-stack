#!/usr/bin/env node
// Development-only: pre-render Kenney's CC0 GLBs, never load Three.js in watch.
// npm install --prefix /some/temp/dir three@0.181.1 playwright@1.56.1
// node scripts/render-watch-characters.mjs <unpacked-pack> <node_modules> <atlas.json>
//
// Atlas v3: every character is rendered at ATLAS_SCALE (default 2) times the
// 96x120 base cell inside a wider frame (v2 clipped hands and heads at the cell
// edges). Each directional sequence is cropped to the union of its frames'
// non-transparent pixels (one crop per sequence keeps the ground anchor stable
// across that clip) and shelf-packed into a per-character WebP sheet. Crisp on
// HiDPI screens and zoomed offices without shipping empty margins.
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const [pack, modules, output] = process.argv.slice(2);
if (!output) throw new Error('Usage: render-watch-characters.mjs <unpacked-pack> <node_modules> <atlas.json>');
const { chromium } = await import(pathToFileURL(resolve(modules, 'playwright/index.mjs')));
const characters = ['character-male-b', 'character-female-b', 'character-female-d',
  'character-male-f', 'character-female-a', 'character-male-d', 'character-robot'];
// sit = seated at the desk; drive = seated with both hands forward, which
// reads as typing at the keyboard while an agent reports work.
const clips = ['idle', 'walk', 'sit', 'drive'];
const directions = [
  { name:'e', yaw:Math.PI/2 }, { name:'se', yaw:Math.PI/4 },
  { name:'s', yaw:0 }, { name:'sw', yaw:-Math.PI/4 },
  { name:'w', yaw:-Math.PI/2 }, { name:'nw', yaw:-Math.PI*3/4 },
  { name:'n', yaw:Math.PI }, { name:'ne', yaw:Math.PI*3/4 },
];
const sequences = clips.flatMap(clip => (['idle','walk'].includes(clip) ? directions : [directions[2]])
  .map(direction => ({ clip, direction:direction.name, yaw:direction.yaw })));
const scale = Number(process.env.ATLAS_SCALE || 2);
const quality = Number(process.env.ATLAS_QUALITY || 0.9);
const base = { width:96, height:120 };
// World units covered by one base cell in the office (unchanged since v2).
const world = { width:80, height:100 };
const frames = 8, maxSheetWidth = 4096;
// Extra render margin around the base cell; cropping removes what stays empty.
const margin = { x:1.8, y:1.4 };
const server = createServer(async (req, res) => {
  try {
    if (req.url === '/') {
      res.setHeader('Content-Type', 'text/html');
      res.end(`<script type="importmap">{"imports":{"three":"/three/build/three.module.js","three/addons/":"/three/examples/jsm/"}}</script>`);
      return;
    }
    const url = decodeURIComponent(req.url.split('?')[0]);
    const root = url.startsWith('/three/') ? resolve(modules, 'three') : resolve(pack, 'Models/GLB format');
    const file = resolve(root, '.' + (url.startsWith('/three/') ? url.slice(6) : url));
    if (relative(root, file).startsWith('..' + sep)) { res.writeHead(403); res.end(); return; }
    res.setHeader('Content-Type', file.endsWith('.js') ? 'text/javascript' :
      file.endsWith('.png') ? 'image/png' : 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
let browser;
try {
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium',
    args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  const atlas = await page.evaluate(async ({ characters, clips, directions, sequences, scale, quality, base, world, frames, maxSheetWidth, margin }) => {
    const THREE = await import('three');
    const { GLTFLoader } = await import('three/addons/loaders/GLTFLoader.js');
    const width = Math.round(base.width * scale * margin.x), height = Math.round(base.height * scale * margin.y);
    const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(1);
    renderer.setSize(width, height);
    renderer.setClearColor(0, 0);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    const scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xffffff, 0x9aa3bc, 2.3));
    const key = new THREE.DirectionalLight(0xffffff, 2.6); key.position.set(3, 5, 4); scene.add(key);
    const fill = new THREE.DirectionalLight(0xb8caff, .6); fill.position.set(-3, 2, -2); scene.add(fill);
    const loader = new GLTFLoader();
    const sources = [];
    for (let c = 0; c < characters.length; c++) {
      const gltf = await loader.loadAsync('/' + characters[c] + '.glb');
      const model = gltf.scene; scene.add(model);
      const bounds = new THREE.Box3().setFromObject(model), size = bounds.getSize(new THREE.Vector3());
      const center = bounds.getCenter(new THREE.Vector3());
      // Same world-to-pixel scale as v2's 96x120 cell; the margin only adds room.
      const span = size.y * 1.28 * margin.y;
      const camera = new THREE.OrthographicCamera(-span * width / height / 2, span * width / height / 2,
        span / 2, -span / 2, .01, 100);
      camera.position.set(center.x, center.y + 3, center.z + 5);
      camera.lookAt(center.x, center.y, center.z);
      camera.updateMatrixWorld();
      const ground = new THREE.Vector3(0, bounds.min.y, 0).project(camera);
      const anchorPx = [(ground.x + 1) / 2 * width, (1 - ground.y) / 2 * height];
      const mixer = new THREE.AnimationMixer(model);
      const tiles = [];
      const edges = [];
      for (const sequence of sequences) {
        model.rotation.y = sequence.yaw;
        const clip = THREE.AnimationClip.findByName(gltf.animations, sequence.clip);
        if (!clip) throw new Error(characters[c] + ': missing ' + sequence.clip);
        mixer.stopAllAction();
        const action = mixer.clipAction(clip); action.reset().play();
        const rendered = [];
        let minX = width, minY = height, maxX = -1, maxY = -1;
        for (let f = 0; f < frames; f++) {
          mixer.setTime(f / frames * clip.duration);
          renderer.render(scene, camera);
          const frame = document.createElement('canvas'); frame.width = width; frame.height = height;
          const fctx = frame.getContext('2d', { willReadFrequently: true });
          fctx.drawImage(renderer.domElement, 0, 0);
          const alpha = fctx.getImageData(0, 0, width, height).data;
          for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
            if (alpha[(y * width + x) * 4 + 3] > 6) {
              if (x < minX) minX = x; if (x > maxX) maxX = x;
              if (y < minY) minY = y; if (y > maxY) maxY = y;
            }
          }
          rendered.push(frame);
        }
        if (minX === 0 || minY === 0 || maxX === width - 1 || maxY === height - 1)
          edges.push(sequence.clip + '-' + sequence.direction);
        const pad = 2;
        const x0 = Math.max(0, minX - pad), y0 = Math.max(0, minY - pad);
        const w = Math.min(width, maxX + pad + 1) - x0, h = Math.min(height, maxY + pad + 1) - y0;
        tiles.push({ rendered, x0, y0, w, h });
      }
      if (edges.length) throw new Error(characters[c] + ' still touches the render frame: ' + edges.join(', '));
      // Shelf-pack each sequence's frames as one horizontal strip.
      let shelfX = 0, shelfY = 0, shelfH = 0, sheetW = 0;
      for (const tile of tiles) {
        const stripW = tile.w * frames;
        if (shelfX && shelfX + stripW > maxSheetWidth) { shelfY += shelfH; shelfX = 0; shelfH = 0; }
        tile.sx = shelfX; tile.sy = shelfY;
        shelfX += stripW; shelfH = Math.max(shelfH, tile.h); sheetW = Math.max(sheetW, shelfX);
      }
      const sheet = document.createElement('canvas');
      sheet.width = sheetW; sheet.height = shelfY + shelfH;
      const sctx = sheet.getContext('2d');
      for (const tile of tiles) tile.rendered.forEach((frame, f) =>
        sctx.drawImage(frame, tile.x0, tile.y0, tile.w, tile.h, tile.sx + f * tile.w, tile.sy, tile.w, tile.h));
      sources.push({ file: characters[c] + '.glb', animations: gltf.animations.map(a => a.name),
        anchor: [anchorPx[0] / width, anchorPx[1] / height], sheet: [sheet.width, sheet.height],
        // [sheetX, sheetY, width, height, anchorX, anchorY] per sequence; frame f is at sheetX + f * width.
        tiles: tiles.map(t => [t.sx, t.sy, t.w, t.h, +(anchorPx[0] - t.x0).toFixed(2), +(anchorPx[1] - t.y0).toFixed(2)]),
        image: sheet.toDataURL('image/webp', quality) });
      scene.remove(model); mixer.uncacheRoot(model);
    }
    return { version:3, scale, base, world, frames, clips, directions:directions.map(d => d.name),
      sequences:sequences.map(({clip,direction}) => ({clip,direction})), sources };
  }, { characters, clips, directions, sequences, scale, quality, base, world, frames, maxSheetWidth, margin });
  await writeFile(output, JSON.stringify(atlas));
  const bytes = atlas.sources.reduce((n, s) => n + s.image.length, 0);
  console.log(`Rendered ${characters.length} Kenney characters × ${sequences.length} directional sequences × ${frames} frames at ${scale}x → ${output} (${(bytes / 1048576).toFixed(1)} MiB of WebP data URLs)`);
  for (const s of atlas.sources) console.log(`  ${s.file}: sheet ${s.sheet.join('×')}`);
} finally {
  if (browser) await browser.close();
  server.close();
}
