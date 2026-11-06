// After `godot --export-pack "Web content"`: writes content.json next to index.html,
// read by the ContentPack autoload (game/app/content_pack.gd) before it fetches the pack.
// `bytes` drives the progress bar (the server may gzip the transfer); `md5` versions the URL.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [dir = 'build/web', file = 'content.pck'] = process.argv.slice(2);
const data = readFileSync(join(dir, file));
const manifest = { file, bytes: data.length, md5: createHash('md5').update(data).digest('hex') };
writeFileSync(join(dir, 'content.json'), JSON.stringify(manifest) + '\n');
console.log(`content.json: ${file} ${(data.length / 1e6).toFixed(1)} MB, md5 ${manifest.md5}`);
