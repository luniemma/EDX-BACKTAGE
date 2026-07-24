const http = require('node:http');

const port = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok' }));
  }
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ service: '${{ values.name }}' }));
});

server.listen(port, () => console.log(`${{ values.name }} listening on ${port}`));
