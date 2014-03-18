fs = require('fs')
Q = require('q')
http = require('http')
connect = require('connect')
request = require('request')
crypto = require('crypto')
natUpnp = require('nat-upnp')
natpmp = require('nat-pmp')
stream = require('stream')
traceroute = require('traceroute')

makeHasher = ->
    xform = new stream.Transform( { objectMode: true } )
    sz = 0
    hsh = crypto.createHash('sha1')
    xform._transform = (chunk, encoding, done) ->
        sz += chunk.length
        hsh.update(chunk)
        this.push(chunk)
        done()
    xform.getHash = () -> hsh.digest('hex')
    xform.getSize = () -> sz
    return xform

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


mapPortWithUpnp = (localPort, extPort) ->
    deferred = Q.defer();
    client = natUpnp.createClient()
    client.portMapping({
        public: extPort,
        private: @localPort,
        ttl: 0 # unlimited
    }, (err, info) =>
        if err then return deferred.reject(err)
        deferred.resolve([extPort, {method:'upnp', info:info}])
    )
    return deferred.promise

mapPortWithNatPnp = (localPort, extPort) ->
    deferred = Q.defer();
    gateway = traceroute.trace('millstonecw.com', {maxHops:1}, (err, hops) ->
        if (err) then return deferred.reject(err)
        gateway = Object.keys(hops[0])[0]
        client = natpmp.connect(gateway)
        client.externalIp( (err, info) ->
            if (err) then return deferred.reject(err)
            ext_ip = info.ip.join('.')
            client.portMapping({ private: localPort, public: extPort, ttl: 3600 }, (err, info) ->
                if (err) then return deferred.reject(err)
                deferred.resolve([info.public, {method:'pnp', gateway:gateway, info:info}])
            )
        )
    )
    return deferred.promise

class PeerServer
    constructor: (@coord, @localPort, @extPortRange) ->

    start: () ->
        http.createServer(connect()
            .use('/serve', (req,res) => @serve(req, res))
            .use('/ping', @ping)
        ).listen(@localPort)
        @expose(4)
        
    expose: (retry_wait) ->
        [minExtPort, maxExtPort] = @extPortRange
        attemptedExtPort = minExtPort + Math.floor(Math.random() * (1 + maxExtPort - minExtPort))

        # upnp is the most common:
        promise = mapPortWithUpnp(@localPort, attemptedExtPort)
        # used by Apple's airport routers:
        promise = promise.fail(=> mapPortWithNatPnp(@localPort, attemptedExtPort))
        # Maybe we aren't NAT'ed at all?:
        promise = promise.fail(=> [@localPort, {method:'no NAT'}])
        promise.then( (pair) =>
            [realExtPort, info] = pair
            console.log 'Requesting server to ping us at ', realExtPort, '; map info: ', info
            @coord.req('update_peer', [], {determine_host:true, port: realExtPort}).then((ping_error) =>
                if ping_error != ''
                    log 'Share port not externally visible', {retry_seconds:retry_wait}
                    setTimeout((=> @expose(retry_wait * 1.5)), retry_wait * 1000)
            )
        )

    ping: (req, res) ->
        res.writeHead(200)
        res.end(JSON.stringify({result:'OK'}))

    serve: (req, res) ->
        if req.url[0] != '/' then throw new Error()
        key = req.url[1...]
        hasher = makeHasher()
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
                @coord.req('fin_act', [req.method, key, auth, hasher.getSize(), hasher.getHash(), status]).done()
                return (res.writeHead(200); res.end())
            switch req.method
                when 'PUT'
                    checkStream(req, callback).pipe(hasher).pipe(fs.createWriteStream(key))
                when 'GET'
                    checkStream(fs.createReadStream(key).pipe(hasher).pipe(res), callback)
                when 'DELETE'
                    fs.unlink(key, callback)
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
        deferred = Q.defer();
        reqStream.completionPromise = deferred.promise
        callback = (err) =>
            log 'http stream ended (err:', err, ')'
            status = if err then err else 'OK'
            okcb = -> if err then deferred.reject(err) else deferred.resolve()
            errcb = (fin_err) -> deferred.reject(fin_err)
            @coord.req('fin_act', [method, key, auth, hashobject.getSize(), hashobject.getHash(), status]).then(okcb, errcb)

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
