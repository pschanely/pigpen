pigpen
======

Cross platform client for the pigpen cloud storage system.


This is a work in progress.  It is not yet ready for public use.


To install with npm (the node.js package manager):

    npm install -g pigpen

Example storage and retrieval:

    $ tar -c /home/phil | openssl enc -des-cbc | pigpen --put key/name/of/my/choosing -k MY_ACCESS_KEY
    enter des-cbc encryption password:
    Verifying - enter des-cbc encryption password:
    
    $ pigpen --get key/name/of/my/choosing -k MY_ACCESS_KEY | openssl enc -des-cbc -d | tar -x
    enter des-cbc decryption password:

OR

    $ pigpen --runserver -k MY_ACCESS_KEY -p 2574
    Listening on *:2574 ...



The runserver command supports WebDAV, which may let you mount the pigpen cloud as a local filesystem

    mount_webdav http://localhost:2574/ /Volumes/pigpen

Optionally, the server may be configured to issue HTTP redirects, causing the client to download the content directly from a chosen cloud peer (making pigpen work as a kind of CDN).  From the client's perspective, this 

, allowing you to use pigpen as a kind of CDN.

As connect middleware:
    pigpen = require('pigpen')
    XXX.use('/remote', pigpen())

Because command line parameters are visible to anyone on the system, it's more secure to put your access key in a configuration file and not supply the -k option to pigpen:

    echo "accesskey: MY_ACCESS_KEY" > ~/.pigpen

To operate as a host (provide your free space to the cloud):

    $ pigpen --host /Volumes/my_share_dir --access-key=MY_ACCESSKEY --target-size=10G

To get account information:

   $ pigpen account -k MY_ACCESS_KEY



Storage is just a redirected PUT
Get is just a redirected GET (with some kind of auth?)
Replication is handled outside (with multi-download HTTP middleware)



Peer client:
  Makes HTTP calls to https://pigpen.com/api/MY_LOGIN/key/name/of/my/choosing
    [ with http header w/ accesskey, to ban certain IPs? ]
  pigpen confirms with a peer and redirects to it (a peer? Can I give multiples?)

Peer host is an HTTP server:
  Requests from pigpen: expect <method> <request uuid>
    [and serve <file>] [# req limit?] [time limit?] [byte range]
  Requests from <ip>:


Download stream protocol with seek?: (there's a HTTP chunking thing we can use to be HTTP compliant)
  read(1024), seek(3478923), read(1024)
  send(data)


For free: elasticsearch, couchdb, WebDAV?, hbase w/ rest
Extra: 

HTTP reduce:
  fn from N streams to one stream.

HTTP proxy cache:
  HTTP backend with an HTTP store. Option for whether the backend might change under us.

HTTP packager:
  expose a large compound archive as different files

HTTP forker:
  read policy: rewritefn[url->url list], (round robin, redirect, parallel?, priority w/ failover)

HTTP sharder:
  shard_fn[url->url list]

HTTP linear scanner?

HTTP failover?

HTTP write buffer:
  with an HTTP cache backend

HTTP literal

HTTP in-memory store

HTTP ratelimit (req -> bucket id)

HTTP value xform (one stream to another)

HTTP key xform

HTTP transform k,v -> [(k,v),..]  ( not GET-able )

HTTP secondary (just fork + xform?)

HTTP qos (req -> priority score)

HTTP 


