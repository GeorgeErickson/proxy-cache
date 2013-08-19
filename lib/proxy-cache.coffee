crypto = require 'crypto'
url = require 'url'
http = require 'http'
stream = require 'stream'
util = require 'util'
argv = require('optimist')
  .usage('Usage $0')
  .default('p', 80)
  .demand('h')
  .argv

_cache = {}

class CacheStream extends stream.Transform
  constructor: (@key, resp) ->
    @resp = 
      headers: resp.headers
      statusCode: resp.statusCode
    super

  _transform: (chunk, encoding, cb) =>
    _cache[@key] = _cache[@key] or
      stream: []
      resp: @resp
    _cache[@key].stream.push [chunk, encoding]
    cb null, chunk


class CacheReader extends stream.Readable
  constructor: (@key) ->
    @index = 0
    super

  _read: =>
    if _cache[@key].stream.length > @index
      data = _cache[@key].stream[@index]
      @push data[0], data[1]
      @index += 1
    else
      @push null

  writeHead: (res) ->
    head = _cache[@key].resp
    res.writeHead head.statusCode, head.headers


server = http.createServer (req, res) ->
  options = 
    host: argv.h
    port: argv.p
    method: req.method
    path: url.parse(req.url).path
    headers: req.headers

  key = crypto.createHash('md5').update(JSON.stringify(options)).digest('hex')

  cached_resp = _cache[key]

  if cached_resp
    cache_reader = new CacheReader(key)
    cache_reader.writeHead res
    cache_reader.pipe res
  else
    external_req = http.request options, (proxy_response) ->
      cache_stream = new CacheStream key, proxy_response
      res.writeHead proxy_response.statusCode, proxy_response.headers
      proxy_response.pipe(cache_stream).pipe res
    req.pipe external_req


server.listen(8080)