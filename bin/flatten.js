#!/usr/bin/env node

var fs = require('fs')
var moduleDeps = require('module-deps')
var browserPack = require('browser-pack')

var output = process.argv.length > 3 ?
  fs.createWriteStream(process.argv[3]) :
  process.stdout

if (process.argv.length > 2) {
  flatten(process.argv[2])
} else {
  var allJs = ''
  process.stdin.on('data', function(data) { allJs += data })
  process.stdin.on('end', function() { flatten(allJs) })
}

function flatten(jsFileData) {
  var packed = browserPack({raw:true})
  var deps = moduleDeps()

  fs.writeFileSync('.dumbjs.flatten', jsFileData)
  deps.end({ file: './.dumbjs.flatten' })

  deps.pipe(packed).pipe(output)

  packed.on('end', function () {
    fs.unlinkSync('.dumbjs.flatten')
  })
}

