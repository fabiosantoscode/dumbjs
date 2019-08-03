#!/usr/bin/env node

require('coffeescript/register')

var es = require('event-stream')
var dumbjs = require('../lib')
var fs = require('fs')

var inpt = process.stdin
var inptFname = '<stdin>'
if (process.argv.length > 2) {
    inpt = fs.createReadStream(process.argv[2])
    inptFname = process.argv[2]
}

var outpt = process.stdout
if (process.argv.length > 3)
    outpt = fs.createWriteStream(process.argv[3])

inpt.pipe(es.wait(function(err, js) {
    if (err) {
        console.error(err)
        return
    }
    process.stdout.write(dumbjs(js.toString('utf-8'), { filename: inptFname }) + '\n')
}))
