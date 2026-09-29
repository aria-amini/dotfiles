const http = require('http')
const port = Number(process.argv[2] || 45523)

// Host-rewrite hop: impeccable serve-question rejects any Host header except
// 127.0.0.1:<port>/localhost, so a tailnet proxy must rewrite it back.
http
	.createServer((req, res) => {
		const headers = { ...req.headers, host: `127.0.0.1:${port}` }
		const proxy = http.request({ host: '127.0.0.1', port, path: req.url, method: req.method, headers }, (up) => {
			res.writeHead(up.statusCode, up.headers)
			up.pipe(res)
		})
		proxy.on('error', () => {
			res.writeHead(502)
			res.end('hop error')
		})
		req.pipe(proxy)
	})
	.listen(45524, '127.0.0.1', () => console.log(`hop 45524 -> ${port}`))
