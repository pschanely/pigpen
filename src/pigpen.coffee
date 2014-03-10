nomnom = require('nomnom')
nconf = require('nconf')
optimist = require('optimist')
fs = require('fs')
path = require('path-extra')
corepeer = require('./corepeer')

require 'coffee-errors'

#
# coffee src/pigpen.coffee share '--accesskey=-g0pTWm5ScSARPMcOaiqgQ==.s-CtmORuWCv4X9aA99qg=='
#
# echo 'hi there' | coffee src/pigpen.coffee put hi.txt '--accesskey=5Lx4bUWsSZ6-Y_yElPm9ow==.J99GvP1wTIOoW2Xy2dj8RA=='
# 


getConfig = () ->
  nomnom.option('help', {abbr:'h'})
  nomnom.help('Interacts with the pigpen cloud storage system.\nRun pigpen <command> -h for more information.\n')
  nomnom.option('accesskey', { abbr:'a', help:'Your access key. It\'s preferred to put this in ~/.pingpen.conf'})
  share = nomnom.command('share')
    .help('Run the share server')
    .option('sharePort', {abbr:'p', help:'The port on which to listen'})
    .option('shareSize', {abbr:'s', help:'Set the target amount of space shared'})
    .option('shareRoot', {abbr:'r', help:'The directory in which to store shared data'})
  proxy = nomnom.command('proxy')
    .help('Run an HTTP server that serves your pigpen files')
    .option('proxyPort', {abbr:'p', help:'The port on which to listen', default:80})
  get = nomnom.command('get')
    .help('Download a file')
  put = nomnom.command('put')
    .help('Upload a file')
    .option('maxSize', {abbr:'p', help:'The maximum size of the upload in GB (used to allocate your file)', default:10})
  list = nomnom.command('list')
    .help('List the files in a directory')
    .option('name', {position:1, help:'The name of the directory in pigpen.'})
  del = nomnom.command('delete')
    .help('Delete a file from pigpen')
  
  for act in [get, put, del]
    act.option('name', {position:1, help:'The name of the file stored in pigpen.'})

  options = nomnom.parse()
  return options


#  args = optimist.options({
#    'k': { alias: 'accesskey', describe: 'Access key given by http://millstonecw.com/pigpen'},
#    'a': { alias: 'action', describe: '"get", "put", or "delete"'},
#    'p': { alias: 'proxy', describe: 'Run the webdav proxy'},
#    's': { alias: 'shareServer', describe: 'Run the share server'},
#    'p': { alias: 'sharePort', describe: 'The port on which to run the share server'},
#    't': { alias: 'targetShareSize', describe: 'Set the target amount of space shared'},
#    'r': { alias: 'shareRoot', describe: 'The directory in which to store shared data'},
#    'h': { alias: 'help'},
#  }).argv
#  
#  nconf
#  .env()
#  .file({ file: path.join(path.homedir(), '.pigpen.json') })
#  .defaults(
#    {
#      sharePort: 45014,
#      extPortMin: 40000,
#      extPortMax: 50000
#    })
#  return (k) -> if args[k] isnt undefined then args[k] else nconf.get(k)

#if conf('help')
#    optimist.showHelp()
#    process.exit(1)

conf = getConfig()
conf.shareExtPortMin ?= 40000
conf.shareExtPortMax ?= 50000
conf.sharePort ?= 45014
conf.coordinatorUrl ?= 'http://pigpen.millstonecw.com:81/api'

[user, pw] = conf.accesskey.split '.'
coord = new corepeer.CoordinatorProxy(conf.coordinatorUrl, user, pw)
api = new corepeer.PigpenApi(coord)
console.log 'CONF',conf
switch conf['0']
  when 'share'
    server = new corepeer.PeerServer(coord, conf.sharePort, [conf.shareExtPortMin, conf.shareExtPortMax])
    server.start()
  when 'get'
    api.get(process.stdout, conf.name)
  when 'put'
    console.log 'starting put'
    api.put(process.stdin, conf.name, conf.maxSize).then(=> console.log 'OK all done')
  when 'delete'
    api.get(conf.name)
  when 'list'
    []
  when 'proxy'
    []
