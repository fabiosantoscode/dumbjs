fs = require 'fs'
ok = require 'assert'
dumbjs = require '..'
topmost = require '../lib/topmost'
esprima = require 'esprima'
escodegen = require 'escodegen'


no_ws = (s) ->
  s.replace(/(\s|\n)+/gm, ' ').replace(/\s*;\s*$/,'').trim()
jseq = (a, b, msg) ->
  ok.equal(no_ws(a), no_ws(b), msg)

compileAndCheck = (before, after, opt = {}) ->
  js = dumbjs(before, opt)
  js = no_ws(js)
    .replace /.+function \(require, module, exports\) \{/, ''
    .replace /\}, \{\} ] \}, \{\}, \[.+/, ''
  jseq js, after

describe 'dumbjs', ->
  it 'turns function declarations into variable declarations', ->
    compileAndCheck '
      function lel () { }',
      'var lel = function () { };',
      { topmost: false }

  it 'removes "use strict" because it\'s always strict', ->
    compileAndCheck '
      "use strict";
      (function() {
        "use strict"
      }());
      ',
      '(function () { }());',
      { topmost: false }

  it 'resolves require() calls with module-deps and browser-pack so as to generate a single output file', () ->
    code = dumbjs 'require("./test/some.js")'  # actual file in this directory
    ok /xfoo/.test code  # known string in other file
    ok /MODULE_NOT_FOUND/.test code  # known string in browserify prelude

  it 'polyfills regexps with xregexp'

  it 'puts functions at the topmost level', () ->
    code1 = esprima.parse '
      function x() {
        function y() {
          return 6;
        }
        return y();
      }
    '

    topmost code1
    code1 = escodegen.generate code1

    jseq code1, '
      function _flatten_0() {
        return 6;
      }
      function x() {
        return _flatten_0();
      }
    '

    code2 = esprima.parse '
      x(function() {
        return 6;
      });
    '

    topmost code2
    code2 = escodegen.generate code2

    jseq code2, '
      var _flatten_0 = function () {
        return 6;
      };
      x(_flatten_0);
    '

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
