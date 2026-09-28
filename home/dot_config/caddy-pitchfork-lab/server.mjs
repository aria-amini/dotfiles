import { createServer } from 'vite';

const server = await createServer({
  configFile: false,
  root: process.env.LAB_FIXTURE || process.cwd(),
  server: {
    host: '127.0.0.1',
    port: Number(process.env.PORT),
    strictPort: true,
    allowedHosts: ['.lab.test', '.caddy-lab.lvh.ariaamini.com'],
  },
  plugins: [{
    name: 'lab-observation',
    configureServer(server) {
      server.middlewares.use('/__lab', (req, res) => {
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({
          cwd: process.cwd(),
          port: Number(process.env.PORT),
          pid: process.pid,
          host: req.headers.host,
          forwardedHost: req.headers['x-forwarded-host'],
          forwardedProto: req.headers['x-forwarded-proto'],
        }));
      });
    },
  }],
});
await server.listen();
