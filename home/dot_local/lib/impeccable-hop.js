const http = require('http')
const enginePort = Number(process.argv[2])
const listenPort = Number(process.argv[3] || enginePort)
const bindHost = process.argv[4] || '0.0.0.0'

// Host-rewrite hop: impeccable serve-question rejects any Host header except
// 127.0.0.1:<port>/localhost, so a raw-IP publish must rewrite it back.
const server = http.createServer((req, res) => {
	const headers = { ...req.headers, host: `127.0.0.1:${enginePort}` }
	const proxy = http.request({ host: '127.0.0.1', port: enginePort, path: req.url, method: req.method, headers }, (up) => {
		res.writeHead(up.statusCode, up.headers)
		up.pipe(res)
	})
	proxy.on('error', () => {
		res.writeHead(502)
		res.end('hop error')
	})
	req.pipe(proxy)
})

server.on('error', (err) => {
	console.error(`hop failed to bind ${bindHost}:${listenPort}: ${err.code}`)
	process.exit(1)
})
server.listen(listenPort, bindHost, () => console.log(`hop ${bindHost}:${listenPort} -> 127.0.0.1:${enginePort}`))
