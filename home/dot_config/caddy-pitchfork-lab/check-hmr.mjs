import https from 'node:https';
import { readFile, writeFile } from 'node:fs/promises';
import WebSocket from 'ws';

const [caFile, fixture] = process.argv.slice(2);
const host = 'web--demo.caddy-lab.lvh.ariaamini.com';
const ca = await readFile(caFile);
const lookup = (_host, options, callback) => options.all
  ? callback(null, [{ address: '127.0.0.1', family: 4 }])
  : callback(null, '127.0.0.1', 4);
const client = await new Promise((resolve, reject) => {
  https.get({ hostname: host, port: 18443, path: '/@vite/client', ca, lookup }, res => {
    let body = '';
    res.on('data', chunk => { body += chunk; });
    res.on('end', () => res.statusCode === 200 ? resolve(body) : reject(new Error(`HTTP ${res.statusCode}`)));
    res.on('error', reject);
  }).on('error', reject);
});
const token = client.match(/const wsToken = "([^"]+)"/)?.[1];
if (!token) throw new Error('Vite WebSocket token absent');
const ws = new WebSocket(`wss://${host}:18443/?token=${token}`, 'vite-hmr', { ca, lookup });
const original = await readFile(fixture, 'utf8');
try {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('HMR timeout')), 10000);
    ws.on('error', reject);
    ws.on('message', async raw => {
      try {
        const message = JSON.parse(raw.toString());
        if (message.type === 'connected') await writeFile(fixture, `${original}\n<!-- HMR probe -->\n`);
        if (message.type === 'full-reload' || message.type === 'update') {
          clearTimeout(timeout);
          console.log(JSON.stringify({ websocket: 'connected', hmr: message.type, path: message.path }));
          resolve();
        }
      } catch (error) { reject(error); }
    });
  });
} finally {
  ws.terminate();
  await writeFile(fixture, original);
}
