fs = require('fs')
Q = require('q')
http = require('http')
connect = require('connect')
request = require('request')
crypto = require('crypto')
natUpnp = require('nat-upnp')
natpmp = require('nat-pmp')

makeHasher = -> crypto.createHash('sha1')

checkStream = (stream, callback) ->
    stream.on('end', callback)
    stream.on('error', (err) -> callback('stream error: '+err))
    return stream

log = (args...) -> console.log(args...)

class CoordServer
    constructor: () ->
    initAction: (user, method, key, data) -> # data undefined in the 'DELETE' case

class CoordinatorProxy
    constructor: (@url, @userid, @password) ->

    req: (method, args, kw) ->
        log 'Coordinator request', {method:method, args:args, kw:kw, baseurl:@url}
        args = [@userid, @password].concat(args)
        req =
            url: @url + '/' + method
            form: {a:JSON.stringify(args),kw:JSON.stringify(kw or {})}
            method: 'POST'
        deferred = Q.defer();
        request(req, (err, response, body) ->
            if (not err) and (200 <= response.statusCode < 300)
                body = JSON.parse(body)
                deferred.resolve(body)
            else
                error = new Error((err or '') + ' ' + (body or ''))
                deferred.reject(error)
            log 'Coordinator response', {err:err, code:(response and response.statusCode), body:body}
        )
        return deferred.promise


mapPortWithPnp = (extPort) ->
    client = natpmp.connect('192.168.2.1');
    client.externalIp( (err, info) ->
        if (err) then throw err
        log('Current external IP address: %s', info.ip.join('.'))
    );
    client.portMapping({ private: @localPort, public: extPort, ttl: 3600 }, (err, info) ->
        if (err) then throw err;
        log(info)
    )




class PeerServer
    constructor: (@coord, @localPort, @extPortRange) ->

    start: (retry_wait) ->
        retry_wait ?= 4
        [minExtPort, maxExtPort] = @extPortRange
        extPort = maxExtPort + Math.floor(Math.random() * (1 + maxExtPort - minExtPort))
        client = natUpnp.createClient()
        client.portMapping({
            public: extPort,
            private: @localPort,
            ttl: 0 # unlimited
        }, (err, extra) =>
            if err
                log 'ERROR: Unable to map ports', {err: err}
                extPort = @localPort
            else
                log 'Port mapped', {internal: @localPort, external: extPort, extra: extra}
            http.createServer(connect().use('/serve', (req,res) => @serve(req, res)).use('/ping', @ping)).listen(@localPort)
            @coord.req('update_peer', [], {determine_host:true, port: extPort}).then((ping_error) =>
                if ping_error != ''
                    log 'Share port not externally visible', {retry_seconds:retry_wait}
                    setTimeout((=> @start(retry_wait * 1.5)), retry_wait * 1000)
            )
            #http.Server(@serve).start() # or ... use the real node.js one, since we're using streams
        )

    ping: (req, res) ->
        res.writeHead(200)
        res.end(JSON.stringify({result:'OK'}))

    serve: (req, res) ->
        if req.url[0] != '/' then throw new Error()
        key = req.url[1...]
        log 'Inbound request', {key:key, headers:req.headers}
        auth = req.headers['x-pigpen-auth']
        @coord.req('chk_act', [req.host, req.method, key, auth]).then( (response) =>
            log 'CHECK ACT ', response, req.method
            if response['result'] != 'OK'
                return (res.writeHead(400); res.end())
            sz = 0; hsh = 0
            callback = (err) =>
                log '311', @coord, 'err:', err
                status = if err then err else 'OK'
                @coord.req('fin_act', [req.method, key, auth, sz, hsh, status]).done()
                return (res.writeHead(200); res.end())
            switch req.method
                when 'PUT'
                    log 'PUTTIN!'
                    checkStream(req, callback).pipe(fs.createWriteStream(key))
                when 'GET' then checkStream(fs.createReadStream(key).pipe(res), callback)
                when 'DELETE' then fs.unlink(key, callback)
        ).done()

class PigpenApi
    constructor: (@coord) ->

    openStream: (method, ukey, estLen, hashobject) ->
        @coord.req('req_act', [method, ukey, estLen], {})
        .then((response) => @openStreamContinuation(method, response, hashobject))

    openStreamContinuation: (method, response, hashobject) ->
        # hashobject.update(response['hashinit']) #TODO
        log 'Coordinator responds to request: ', response
        if response['result'] != 'OK'
            throw new Exception('Coordinator rejected')
        url = 'http://' + response['host'] + ':' + response['port'] + '/serve/' + response['key']
        key = response['key']
        auth = response['auth']
        reqStream = request[method.toLowerCase()]({url:url, headers:{'x-pigpen-auth': auth}})
        sz = 0
        deferred = Q.defer();
        reqStream.completionPromise = deferred.promise
        callback = (err) =>
            log 'http stream ended (err:', err, ')'
            status = if err then err else 'OK'
            okcb = -> if err then deferred.reject(err) else deferred.resolve()
            errcb = (fin_err) -> deferred.reject(fin_err)
            @coord.req('fin_act', [method, key, auth, sz, hashobject.read(), status]).then(okcb, errcb)

        reqStream.on('data', (chunk) ->
            log 'response? data chunk : ', chunk
            sz += chunk.length)
        reqStream.on('end', (chunk) ->
            log 'end chunk : ', chunk
            callback())
        reqStream.on('error', (err) -> callback('stream error: '+err))
        return reqStream

    put: (stream, key, estLen) ->
        hasher = makeHasher()
        @openStream('PUT', key, estLen, hasher).then( (putstream) ->
            stream.pipe(hasher).pipe(putstream)
            return putstream.completionPromise
        )

    get: (stream, key) ->
        hasher = makeHasher()
        @openStream('GET', key, estLen, hasher).then((getstream) ->
            getstream.pipe(hasher).pipe(stream); getstream.completionPromise)

    delete: (key) ->
        @openStream('DELETE', key, estLen).then((stream) ->
            stream.completionPromise)

exports.CoordinatorProxy = CoordinatorProxy
exports.PigpenApi = PigpenApi
exports.PeerServer = PeerServer
