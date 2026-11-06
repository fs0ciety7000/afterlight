// Minimal static server for the Godot web export (no dependencies).
// Gzips .wasm/.js/.html/.pck (index.pck, then content.pck fetched by the title) when the browser accepts it, like any static host would: the
// download a player waits for (docs/ARCHITECTURE.md "Taille de l'export") is the gzipped size.
import { createReadStream, existsSync, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import { gzipSync } from 'node:zlib';

const [root = 'build/web', port = '8060'] = process.argv.slice(2);
const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json',
};
const compressible = new Set(['.html', '.js', '.wasm', '.pck']);
const gzCache = new Map(); // file -> { mtimeMs, body }

function gzipped(file, stat) {
  const hit = gzCache.get(file);
  if (hit && hit.mtimeMs === stat.mtimeMs) return hit.body;
  const body = gzipSync(readFileSync(file), { level: 6 });
  gzCache.set(file, { mtimeMs: stat.mtimeMs, body });
  return body;
}

createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  const rel = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
  let file = join(root, rel || 'index.html');
  if (!file.startsWith(normalize(root))) { res.writeHead(403).end(); return; }
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  if (!existsSync(file)) { res.writeHead(404).end(); return; }
  const ext = extname(file);
  const headers = { 'Content-Type': types[ext] ?? 'application/octet-stream' };
  if (compressible.has(ext) && /\bgzip\b/.test(req.headers['accept-encoding'] ?? '')) {
    const body = gzipped(file, statSync(file));
    res.writeHead(200, { ...headers, 'Content-Encoding': 'gzip', 'Content-Length': body.length, Vary: 'Accept-Encoding' });
    res.end(body);
    return;
  }
  res.writeHead(200, headers);
  createReadStream(file).pipe(res);
}).listen(Number(port), () => console.log(`Serving ${root} on http://localhost:${port}`));
