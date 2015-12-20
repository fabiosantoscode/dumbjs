fs = require 'fs'
ok = require 'assert'
estraverse = require 'estraverse'
dumbjs = require '..'
topmost = require '../lib/topmost'
declosurify = require '../lib/declosurify'
ownfunction = require '../lib/ownfunction'
bindify = require '../lib/bindify.coffee'
bindifyPrelude = require '../lib/bindify-prelude.coffee'
depropinator = require '../lib/depropinator.coffee'
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
      { topmost: false, declosurify: false, mainify: false, }

  it 'removes "use strict" because it\'s always strict', ->
    compileAndCheck '
      "use strict";
      (function() {
        "use strict"
      }());
      ',
      '(function () { }());',
      { topmost: false, declosurify: false, mainify: false, }

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

  it 'renames not only references to functions, but references to the current function, lexical style', () ->
    code1 = esprima.parse '
      function x() {
        function y() {
          return y();
        }
      }
    '

    topmost code1
    code1 = escodegen.generate code1

    jseq code1, '
      function _flatten_0() {
        return _flatten_0();
      }
      function x() {
      }
    '

  it 'regression: doesnt mix flatten with _closure', () ->
    code1 = esprima.parse '
      function lel1() {
        var x = 60;
        function lel2() {
          return x;
        }
        return lel2
      }
    '
    topmost code1
    code1 = escodegen.generate code1
    jseq(code1, '
      function _flatten_0() {
        return x;
      }
      function lel1() {
        var x = 60;
        return _flatten_0;
      }
    ')

  it 'creates objects for closures, turns every reference into an object access', () ->
    code1 = esprima.parse '
      function x() {
        var foo = 5,
            bar = 6;
        function y() {
          return foo + bar;
        }
        foo = 6;
        return y;
      }
    '

    declosurify code1, { params: false, fname: false, recursiveClosures: false }
    code1 = escodegen.generate code1

    jseq code1, '
      function x() {
        var _closure_0 = {};
        _closure_0.foo = 5;
        _closure_0.bar = 6;
        function y() {
          return _closure_0.foo + _closure_0.bar;
        }
        _closure_0.foo = 6;
        return _closure_0.y;
      }
    '

  it 'puts accesses to own function name in the outside closure, in a variable named _ownfunction_*', () ->
    code1 = esprima.parse '
      function x() {
        function y() {
          return y()
        }
        foo(function zed() {
          return zed()
        });
        function immune1() {
          
        }
        foo(function immune2() {
          
        });
      }
    '

    ownfunction code1
    code1 = escodegen.generate code1

    jseq(code1, '
      function x() {
        var _ownfunction_0 = y;
        function y() {
          return _ownfunction_0();
        }
        var _ownfunction_1 = function zed() {
          return _ownfunction_1();
        };
        foo(_ownfunction_1);
        function immune1() {
          
        }
        foo(function immune2() {
          
        });
      }
    ')

  it 'can also turn function decls (IE: not variable decls) into object assignments'

  it 'makes non-top functions take a "_closure" parameter which is the upper closure', () ->
    code1 = esprima.parse '
      function x() {
        var foo = 5;
        function y() {
          var kek = 6;
          return foo + kek;
        }
      }
    '

    declosurify code1, { params: false, fname: false }
    code1 = escodegen.generate code1

    jseq code1, '
      function x() {
        var _closure_0 = {};
        _closure_0.foo = 5;
        function y(_closure) {
          var kek = 6;
          return _closure.foo + kek;
        }
      }
    '

  it 'doesn\'t pass an upper closure and don\'t build your own closure if it\'s not needed', () ->
    code1 = esprima.parse '
      function immune1() { }
      function immune15() { function xx(y) { var x; return x; } }
      function immune2() {
        function immuneToGetting() {
          var x = 10;
          return function immuneToPassing() {
            function dontpassme() {
              return 5;
            }
            return x;
          };
        }
      }
    '

    declosurify code1, { params: false, fname: false }

    code1 = escodegen.generate code1

    jseq code1, '
      function immune1() { }
      function immune15() { function xx(y) { var x; return x; } }
      function immune2() {
        function immuneToGetting() {
          var _closure_0 = {};
          _closure_0.x = 10;
          return function immuneToPassing(_closure) {
            function dontpassme() {
              return 5;
            }
            return _closure.x;
          };
        }
      }
    '

  it 'regression: doesnt refer to _closure when theres none', () ->
    code1 = esprima.parse '
      function thing(x) {
        function y() {
          return x - 1
        }
        return y()
      }
    '

    declosurify code1
    code1 = escodegen.generate code1

    jseq code1, '
      function thing(x) {
        var _closure_0 = {};
        _closure_0.x = x;
        _closure_0.y = y;
        function y(_closure) {
          return _closure.x - 1;
        }
        return _closure_0.y();
      }
    '

  it 'Assigns closures above it to its own closure', () ->
    code1 = esprima.parse '
      function x() {
        return function y() {
        }
      }
    '

    declosurify code1, { fname: false, params: false, always_create_closures: true }
    code1 = escodegen.generate code1

    jseq code1, '
      function x() {
        var _closure_0 = {};
        return function y(_closure) {
          var _closure_1 = {};
          _closure_1._closure_0 = _closure;
        };
      }
    '

  it 'deeply assigns closures above it to its own closure', () ->
    code1 = esprima.parse '
      function x() {
        return function y() {
          return function z() {
            return function g() {
              
            }
          }
        }
      }
    '

    declosurify code1, { fname: false, params: false, always_create_closures: true }
    code1 = escodegen.generate code1

    jseq code1, '
      function x() {
        var _closure_0 = {};
        return function y(_closure) {
          var _closure_1 = {};
          _closure_1._closure_0 = _closure;
          return function z(_closure) {
            var _closure_2 = {};
            _closure_2._closure_1 = _closure;
            _closure_2._closure_0 = _closure._closure_0;
            return function g(_closure) {
              var _closure_3 = {};
              _closure_3._closure_2 = _closure;
              _closure_3._closure_1 = _closure._closure_1;
              _closure_3._closure_0 = _closure._closure_0;
            };
          };
        };
      }
    '

  it 'puts parameters and the function name in its closure object as well', () ->
    code1 = esprima.parse '
      function x(a) {
        function y(z) {
          return a(y)(z);
        }
      }
    '

    declosurify code1, { recursiveClosures: false }
    code1 = escodegen.generate code1

    jseq code1, '
      function x(a) {
        var _closure_0 = {};
        _closure_0.a = a;
        _closure_0.y = y;
        function y(z) {
          return _closure_0.a(_closure_0.y)(z);
        }
      }
    '

  it 'regression: declarations inside for loops', () ->
    code1 = esprima.parse '
      function x() {
        for (var y = 0; i < 10; i++) {
        }
        for (var z, t = 6; i < 10; i++) {
        }
      }
    '
    declosurify code1, { fname: false, params: false, always_create_closures: true }
    code1 = escodegen.generate code1
    jseq(code1, '
      function x() {
        var _closure_0 = {};
        _closure_0.y = 0;
        for (; i < 10; i++) {
        }
        _closure_0.z = undefined;
        _closure_0.t = 6;
        for (; i < 10; i++) {
        }
      }
    ')


  it 'binds _flatten_* function to their current _closure_*', () ->
    code1 = esprima.parse '
      function _flatten_0(_closure) { return _closure_0.x; }
      function x() {
        var _closure_0;
        return _flatten_0;
      }
    '

    bindify code1
    code1 = escodegen.generate code1

    jseq code1, '
      function _flatten_0(_closure) {
        return _closure_0.x;
      }
      function x() {
        var _closure_0;
        return BIND(_flatten_0, _closure_0);
      }
    '

  it 'binds only to functions which have a _closure argument', () ->
    code1 = esprima.parse '
      function _flatten_0(_closure) { return _closure_0.x; }
      function _flatten_immune() { return _closure_0.x; }
      function _flatten_immune_2(_closure1) { return _closure_0.x; }
      function x() {
        var _closure_0;
        return _flatten_0;
        return _flatten_immune;
        return _flatten_immune_2;
      }
    '

    bindify code1
    code1 = escodegen.generate code1

    jseq code1, '
      function _flatten_0(_closure) { return _closure_0.x; }
      function _flatten_immune() { return _closure_0.x; }
      function _flatten_immune_2(_closure1) { return _closure_0.x; }
      function x() {
        var _closure_0;
        return BIND(_flatten_0, _closure_0);
        return _flatten_immune;
        return _flatten_immune_2;
      }
    '

  it 'Turns object declarations into iifes', () ->
    code1 = esprima.parse '
      var x = { foo: "bar", baz: -1 };
    '

    depropinator code1
    code1 = escodegen.generate code1

    jseq code1, '
      var x = function () {
        var ret = {};
        ret.foo = \'bar\';
        ret.baz = -1;
        return ret;
      }()
    '

  it 'screams at you for using globals'

  it 'screams at you for using eval, arguments, this, reserved names (_closure_, _closure, _flatten_, _ownfunction_)'

  it 'doesnt let you subscript stuff with anything other than numbers or letters (IE: not strings, not expressions)'

  it 'puts all program code in the bottom of everything into a function called "main"'

describe 'functional tests', () ->
  it 'its code runs on node', () ->
    hi = null
    eval(bindifyPrelude + dumbjs('(function(){ hi = "hi" }())') + ';main()')
    ok.equal(hi, 'hi')

  it 'passing functions works', () ->
    arr = []
    eval(bindifyPrelude + dumbjs('''
      function pushr(x) {
        arr.push(x())
      }

      pushr(function(){ return 1 })
      pushr(function(){ return 2 })
    ''') + ';main()')

    ok.deepEqual(arr, [1,2])

  it 'using recursion works', () ->
    FACT = 0
    eval(bindifyPrelude + dumbjs('''
      FACT = (function factorial(n) {
        if (n < 1) {
          return 1;
        }
        return n * factorial(n - 1)
      }(4));
    ''') + ';main()')

    ok.equal(FACT, 24)

  it 'using closures works', () ->
    arr = []

    eval(bindifyPrelude + dumbjs('''
      var to_call_later = [];
      function pushr(x) {
        to_call_later.push(function() { arr.push(x()) })
      }

      pushr(function(){ return 1 });
      pushr(function(){ return 2 });

      for (var i = 0; i < to_call_later.length; i++) {
        to_call_later[i]();
      }
    ''') + ';main()')

    ok.deepEqual(arr, [1,2])

  it 'regression: trying to access _closure parameter when there is none', () ->
    first_chunk = '''
      function fib(n) {
        return n == 0 ? 0 :
          n == 1 ? 1 :
                fib(n - 1) + fib(n - 2)
      }
    '''
    second_chunk = '''
      function inc(start) {
        // Featuring level 2 closures!
        return function bar() {
          return start++
        }
      }
      var incrementor = inc(-1)
      arr.push(incrementor())
      arr.push(incrementor())
      arr.push(incrementor())
    '''

    jseq(dumbjs(first_chunk + second_chunk), '''
      var _flatten_1 = function bar(_closure) {
          return _closure.start++;
      };
      var _flatten_2 = function (start) {
          var _closure_1 = {};
          _closure_1.start = start;
          return BIND(_flatten_1, _closure_1);
      };
      var _flatten_0 = function (_closure, n) {
          return n == 0 ? 0 : n == 1 ? 1 : _closure._ownfunction_0(n - 1) + _closure._ownfunction_0(n - 2);
      };
      var main = function () {
          var _closure_0 = {};
          _closure_0.fib = BIND(_flatten_0, _closure_0);
          _closure_0.inc = _flatten_2;
          _closure_0._ownfunction_0 = _closure_0.fib;
          _closure_0.incrementor = _closure_0.inc(-1);
          arr.push(_closure_0.incrementor());
          arr.push(_closure_0.incrementor());
          arr.push(_closure_0.incrementor());
      };
    ''')

    arr = []
    eval(bindifyPrelude + dumbjs(first_chunk + second_chunk) + ';main()')
    ok.deepEqual(
      arr,
      [-1, 0, 1]
    )

    arr = []
    eval(bindifyPrelude + dumbjs(first_chunk + 'arr.push(fib(4))') + ';main()')
    ok.equal(arr[0], 3)

