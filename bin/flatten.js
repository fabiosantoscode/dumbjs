#!/usr/bin/env node

var fs = require('fs')
var es = require('event-stream')
var moduleDeps = require('module-deps')
var browserPack = require('browser-pack')

function flatten(jsFileData) {
  var packed = browserPack({raw:true})
  var deps = moduleDeps()

  fs.writeFileSync('.dumbjs.flatten', jsFileData)
  deps.end({ file: './.dumbjs.flatten' })

  packed.on('end', function () {
    fs.unlinkSync('.dumbjs.flatten')
  })

  return deps.pipe(packed)
}

module.exports = flatten

if (module.parent == null) {
  var input = process.argv.length > 2 ?
    fs.createReadStream(process.argv[2]) :
    process.stdin

  var output = process.argv.length > 3 ?
    fs.createWriteStream(process.argv[3]) :
    process.stdout

  input.pipe(es.wait(function (err, allJs) {
    if (err) {
      console.error(err)
      process.exit(1)
    }
    flatten(allJs).pipe(output)
  }))
}
