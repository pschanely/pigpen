pigpen = require('../src/corepeer')
fs = require('fs')
streamifier = require('streamifier')

require 'coffee-errors'

success = (promisefn) ->
    done = false
    error = null
    promise = promisefn().then(
        (args...) ->
            console.log 'DONE:', args
            done = true
        ,
        (e) ->
            e ||= 'error'
            console.log(e.stack)
            error = e
            done = true
        )
    waitsFor(-> done)
    runs(->
        if error
            throw error
        )


# -g0pTWm5ScSARPMcOaiqgQ==
# {"unallocated_sz": 25408011264.0,
#  "peer_id": "-g0pTWm5ScSARPMcOaiqgQ==",
#  "share_sz": 25408011264.0,
#  "port": 10262,
#  "host": "68.198.31.11",
#  "password": "s-CtmO-qRuWCv4X9aA99qg==",
#  "email": "pschanely@gmail.com"}
# 

describe 'PigpenApi', ->
    it 'works', -> success ->
        coord = new pigpen.CoordinatorProxy(
            'http://pigpen.millstonecw.com:81/api',
            '-g0pTWm5ScSARPMcOaiqgQ==',
            's-CtmO-qRuWCv4X9aA99qg==')
        api = new pigpen.PigpenApi(coord)
        api.put(streamifier.createReadStream('my data'), 'mykey01', 7)

