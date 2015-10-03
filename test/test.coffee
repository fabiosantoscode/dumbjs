fs = require 'fs'
ok = require 'assert'
dumbjs = require '..'

no_ws = (s) ->
  s.replace(/(\s|\n)+/gm, ' ').replace(/\s*;\s*$/,'').trim()
jseq = (a, b, msg) ->
  ok.equal(no_ws(a), no_ws(b), msg)

compileAndCheck = (before, after) ->
  js = dumbjs(before)
  js = no_ws(js)
    .replace /.+function \(require, module, exports\) \{/, ''
    .replace /\}, \{\} ] \}, \{\}, \[.+/, ''
  jseq js, after

describe 'dumbjs', ->
  it 'turns function declarations into variable declarations', ->
    compileAndCheck '
      function lel () { }',
      'var lel = function () { };'

  it 'removes "use strict" because it\'s always strict', ->
    compileAndCheck '
      "use strict";
      (function() {
        "use strict"
      }());
      ',
      '(function () { }());'

  it 'resolves require() calls with module-deps and browser-pack so as to generate a single output file', () ->
    code = dumbjs 'require("./test/some.js")'  # actual file in this directory
    ok /xfoo/.test code  # known string in other file
    ok /MODULE_NOT_FOUND/.test code  # known string in browserify prelude

  it 'polyfills regexps with xregexp'

  it 'turns array objects into function calls'

  it 'turns object expressions into function calls'

  it 'puts functions at the topmost level'

  it 'knows to rename functions when shoving them up'

  it 'screams at you for using globals'

  it 'doesnt let you subscript stuff with anything other than numbers or letters (IE: not strings, not expressions)'

  it 'puts all program code in the bottom of everything into a function called "main"'

describe 'functional tests', () ->
  it 'its code runs on node', () ->
    hi = null
    eval dumbjs '(function(){ hi = "hi" }())'
    ok.equal(hi, 'hi')

  it 'using closures works'
    # arr = []
    # eval dumbjs '''
    #   function pushr(x) {
    #     arr.push(x())
    #   }

    #   pushr(function(){ return 1 })
    #   pushr(function(){ return 2 })
    # '''

    # ok.deepEqual(arr, [1,2])

    # arr = []

    # eval dumbjs '''
    #   var to_call_later = []
    #   function pushr(x) {
    #     to_call_later.push(function() { arr.push(x()) })
    #   }

    #   pushr(function(){ return 1 })
    #   pushr(function(){ return 2 })

    #   for (var i = 0; i < to_call_later.length; i++) {
    #     to_call_later[i]()
    #   }
    # '''

    # ok.deepEqual(arr, [1,2])
