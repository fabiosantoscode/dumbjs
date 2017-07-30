fs = require 'fs'
es = require 'event-stream'
ok = require 'assert'
estraverse = require 'estraverse'
dumbjs = require '../lib'
requireObliteratinator = require '../lib/require-obliteratinator'
typeConversions = require '../lib/type-conversions'
topmost = require '../lib/topmost'
declosurify = require '../lib/declosurify'
ownfunction = require '../lib/ownfunction'
thatter = require '../lib/thatter'
bindify = require '../lib/bindify'
bindifyPrelude = require '../lib/bindify-prelude'
depropinator = require '../lib/depropinator'
deregexenise = require '../lib/deregexenise'
esprima = require 'esprima'
escodegen = require 'escodegen'

clean_ast = (ast) ->
  estraverse.traverse(ast, {
    leave: (node) ->
      delete node.scope
      delete node.objType
  })
  return ast

generate_if_needed = (s) ->
  if typeof s is 'string'
    s
  else
    escodegen.generate(s)

parse_if_needed = (s) ->
  if typeof s is 'string'
    esprima.parse(s)
  else
    s

no_ws = (s) ->
  s.replace(/(\s|\n)+/gm, ' ').replace(/\s*;\s*$/,'').trim()
jseq = (a, b, msg) ->
  try
    s_a = no_ws(generate_if_needed(a))
    s_b = no_ws(generate_if_needed(b))
  catch e
    ok.deepEqual(clean_ast(parse_if_needed(a)), clean_ast(parse_if_needed(b)), msg)
    ok false
    return
  ok.equal(s_a, s_b, msg)

compileAndCheck = (before, after, opt = {}) ->
  callAndCheck(before, dumbjs, after, opt)

callAndCheck = (before, fn, after, opt = {}) ->
  js = fn(before, opt)
  js = no_ws(js)
    .replace /.+function \(require, module, exports\) \{/, ''
    .replace /\}, \{\} ] \}, \{\}, \[.+/, ''
  jseq js, after

describe 'core', ->
  it 'turns function declarations into variable declarations', ->
    compileAndCheck 'function lel () { }',
      'var lel = function () { };',
      { topmost: false, declosurify: false, mainify: false, }

  it 'turns multi-variable declarations into multiple single variable declarations', ->
    compileAndCheck 'var x, y = 6',
      'var x; var y = 6;',
      { topmost: false, declosurify: false, mainify: false, }

    compileAndCheck 'for (var x, y = 6;;){}',
      'var x; var y = 6; for (;;) { }',
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

  it 'can pass for..in statements through', () ->
    compileAndCheck '
      for (var x in y) {}
    ', '
      for (var x in  y) { }
    ', { mainify: false }

    compileAndCheck '
      function a() {
        for (var x in y) {
          function _x() {
            console.log(x)
          }
          _x()
        }
      }
    ', '
      var _flatten__x = function (_closure) { console.log(_closure.x); };
      var a = function () {
        var _closure_0 = {};
        for (var _for_in_0 in y) {
          _closure_0.x = _for_in_0;
          _flatten__x(_closure_0);
        }
      }
    ', { mainify: false }

  it.skip 'refrains from messing with variable declarations in fors as well', () ->
    compileAndCheck '
      function a() {
        for (var x = 123;;) {
          function _x() {
            console.log(x)
          }
          _x()
        }
      }
    ', '
      var _flatten__x = function (_closure) { console.log(_closure.x); };
      var a = function () {
        var _closure_0 = {};
        for (_closure_0.x = 123;;) {
          _flatten__x(_closure_0);
        }
      }
    ', { mainify: false }

describe 'typeConversions', () ->
  it 'turns numbers into strings when adding them to strings', ->
    code1 = esprima.parse '
      var x = 1;
      x + \'\';
      \'\' + x + 2 + 3;
      1 + \'\' + 1;
    '

    typeConversions code1
    code1 = escodegen.generate code1

    jseq code1, '
      var x = 1;
      String(x) + \'\';
      \'\' + String(x) + String(2) + String(3);
      String(1) + \'\' + String(1);
    '

  it 'turns strings into numbers when dividing, subtracting or multiplying', ->
    code1 = esprima.parse '
      var x = \'2\';
      x * 2;
      x / 2;
      x - 2;
      2 * x;
      2 / x;
      2 - x;
    '

    typeConversions code1
    code1 = escodegen.generate code1

    jseq code1, '
      var x = \'2\';
      Number(x) * 2;
      Number(x) / 2;
      Number(x) - 2;
      2 * Number(x);
      2 / Number(x);
      2 - Number(x);
    '

  it 'weird precedence rules', ->
    code1 = esprima.parse '
      1 / 2 + \'\';
      \'\' + 1 / 2;
      1 + 1 + \'\';
      \'\' + 1 + 1;
    '

    typeConversions code1
    code1 = escodegen.generate code1

    jseq code1, '
      String(1 / 2) + \'\';
      \'\' + String(1 / 2);
      String(1 + 1) + \'\';
      \'\' + String(1) + String(1);
    '

  it 'knows the +/- unary operators need conversion to "Number"', ->
    code1 = esprima.parse '
      +foo;
      -bar;
    '

    typeConversions code1
    code1 = escodegen.generate code1

    jseq code1, '
      Number(foo);
      -Number(bar);
    '

  it 'Works on objects, functions, null and undefined', ->
    code1 = esprima.parse '
      null + 2;
      undefined + 2;
      (function(){}) + 2;
      ({}) + 2;
      null * 2;
      undefined * 2;
      (function(){}) * 2;
      ({}) * 2;
      null * null;
      undefined * null;
      (function(){}) * null;
      ({}) * null;
      null * undefined;
      undefined * undefined;
      (function(){}) * undefined;
      ({}) * undefined;
      null * (function(){});
      undefined * (function(){});
      (function(){}) * (function(){});
      ({}) * (function(){});
      null * ({});
      undefined * ({});
      (function(){}) * ({});
      ({}) * ({});
      null + null;
      undefined + null;
      (function(){}) + null;
      ({}) + null;
      null + undefined;
      undefined + undefined;
      (function(){}) + undefined;
      ({}) + undefined;
      null + (function(){});
      undefined + (function(){});
      (function(){}) + (function(){});
      ({}) + (function(){});
      null + ({});
      undefined + ({});
      (function(){}) + ({});
      ({}) + ({});
    '

    typeConversions code1
    code1 = escodegen.generate code1

    jseq code1, '
      JS_ADD(null, 2);
      JS_ADD(undefined, 2);
      String(function () { }) + String(2);
      String({}) + String(2);
      Number(null) * 2;
      Number(undefined) * 2;
      Number(function () { }) * 2;
      Number({}) * 2;
      Number(null) * Number(null);
      Number(undefined) * Number(null);
      Number(function () { }) * Number(null);
      Number({}) * Number(null);
      Number(null) * Number(undefined);
      Number(undefined) * Number(undefined);
      Number(function () { }) * Number(undefined);
      Number({}) * Number(undefined);
      Number(null) * Number(function () { });
      Number(undefined) * Number(function () { });
      Number(function () { }) * Number(function () { });
      Number({}) * Number(function () { });
      Number(null) * Number({});
      Number(undefined) * Number({});
      Number(function () { }) * Number({});
      Number({}) * Number({});
      JS_ADD(null, null);
      JS_ADD(undefined, null);
      JS_ADD(function () { }, null);
      JS_ADD({}, null);
      JS_ADD(null, undefined);
      JS_ADD(undefined, undefined);
      JS_ADD(function () { }, undefined);
      JS_ADD({}, undefined);
      JS_ADD(null, function () { });
      JS_ADD(undefined, function () { });
      String(function () { }) + String(function () { });
      String({}) + String(function () { });
      JS_ADD(null, {});
      JS_ADD(undefined, {});
      String(function () { }) + String({});
      String({}) + String({});
    '


describe 'topmost', () ->
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
      function _flatten_y() {
        return 6;
      }
      function x() {
        return _flatten_y();
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

  it 'regression: renames all functions, even if they contain named functions.', () ->
    # This bug is caused by using escope's scope = scope.upper to
    # return to the upper scope when inside a function. This
    # doesn't work because not only functions have closures. In
    # fact, named functions appear to have an extra escope scope
    # wherein their name can be used.
    code1 = esprima.parse '
      function main() {
        function maker2() {
            return function objectMaker(_closure) {
                return function (_closure) {
                    return 3;
                };
            };
        }
        maker2(5);
      }
    '

    topmost code1
    code1 = escodegen.generate code1

    jseq code1, '
      var _flatten_objectMaker = function objectMaker(_closure) {
          return _flatten_0;
      };
      var _flatten_0 = function (_closure) {
          return 3;
      };
      function _flatten_maker2() {
          return _flatten_objectMaker;
      }
      function main() {
          _flatten_maker2(5);
      }
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
      function _flatten_y() {
        return _flatten_y();
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
      function _flatten_lel2() {
        return x;
      }
      function lel1() {
        var x = 60;
        return _flatten_lel2;
      }
    ')

describe 'ownfunction', () ->
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

describe 'deregexenise', () ->
  it 'replaces regexen with new RegExp()', () ->
    code1 = esprima.parse '
      /regex/gi
    '

    deregexenise code1
    code1 = escodegen.generate code1

    jseq code1, "
      new RegExp('regex', 'gi')
    "
  it 'does that without regex flags as well', () ->
    code1 = esprima.parse '
      /regex/
    '

    deregexenise code1
    code1 = escodegen.generate code1

    jseq code1, "
      new RegExp('regex')
    "

describe 'declosurify', () ->
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
        return y;
      }
    '

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
        function y(_closure) {
          return _closure.x - 1;
        }
        return y();
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

  it 'knows which variables to put in _closure', () ->
    code1 = esprima.parse '
      function passesZee() {
        var y = 4;
        var z = 6;
        return function foo() {
          return z;
        }
      }
    '

    declosurify code1, { fname: false, params: false }
    code1 = escodegen.generate code1

    jseq code1, '
      function passesZee() {
        var _closure_0 = {};
        var y = 4;
        _closure_0.z = 6;
        return function foo(_closure) {
          return _closure.z;
        };
      }
    '

  it 'Works okay even if the function doesn\'t use the closure but passes it', () ->
    code1 = esprima.parse '
      function x(foo) {
        return function passClosureThrough() {
          return function passMe() {
            return ++foo
          }
        }
      }
    '

    declosurify code1
    code1 = escodegen.generate code1

    jseq code1, '
      function x(foo) {
        var _closure_0 = {};
        _closure_0.foo = foo;
        return function passClosureThrough(_closure) {
          var _closure_1 = {};
          _closure_1._closure_0 = _closure;
          return function passMe(_closure) {
            return ++_closure._closure_0.foo;
          };
        };
      }
    '

  it 'regression: Only closurify identifiers which are references to variables', () ->
    code1 = esprima.parse '
      function x() {
        var EventEmitter = function EventEmitter() {
        };
        EventEmitter.EventEmitter = EventEmitter;
        var defaultMaxListeners = 10;
        var $getMaxListeners = function $getMaxListeners(that) {
          if (that._maxListeners === undefined)
            return EventEmitter.defaultMaxListeners;
          return that._maxListeners;
        };
      }
    '

    declosurify code1
    code1 = escodegen.generate code1

    jseq code1, '
      function x() {
        var _closure_0 = {};
        _closure_0.EventEmitter = function EventEmitter() {
        };
        _closure_0.EventEmitter.EventEmitter = _closure_0.EventEmitter;
        var defaultMaxListeners = 10;
        var $getMaxListeners = function $getMaxListeners(_closure, that) {
          if (that._maxListeners === undefined)
            return _closure.EventEmitter.defaultMaxListeners;
          return that._maxListeners;
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

  it 'regression: if closures aren\'t continuously needed up to the root, don\'t try to access them', () ->
    code1 = esprima.parse '
      function main() {
        function maker4(start) {
          return (function(){
            return function() {
              return start;
            };
          }());
        }
        function xaero(n) {
          return obj;
        }
        var obj = maker4(5);
      }
    '
    declosurify code1
    code1 = escodegen.generate code1
    jseq(code1, '
      function main() {
        var _closure_0 = {};
        function maker4(start) {
          var _closure_1 = {};
          _closure_1.start = start;
          return function (_closure) {
            var _closure_2 = {};
            _closure_2._closure_1 = _closure;
            return function (_closure) {
              return _closure._closure_1.start;
            };
          }();
        }
        function xaero(_closure, n) {
          return _closure.obj;
        }
        _closure_0.obj = maker4(5);
      }
    ')

describe 'bindify', () ->
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

  it 'regression: doesn\'t try to look for _closure_# in function-expression-name scopes. wtf!', () ->
    code1 = esprima.parse '
      var _flatten_0 = function (_closure) { };
      var _flatten_1 = function hiImAFunctionName(_closure) {
          var _closure_1 = {};
          return _flatten_0;
      };
    '

    bindify code1
    code1 = escodegen.generate code1

    jseq code1, '
      var _flatten_0 = function (_closure) { };
      var _flatten_1 = function hiImAFunctionName(_closure) {
          var _closure_1 = {};
          return BIND(_flatten_0, _closure_1);
      };
    '

  it 'avoids writing BIND(_closure, XXX)(ARGS...), just writes XXX(_closure, ARGS...)', () ->
    code1 = esprima.parse '
      var _closure_0 = {};
      _closure_0.prefix = \'-\';
      var _flatten_x = function x(_closure, a) {
        return prefix + typeof a;
      };
      _flatten_x(1);
    '

    bindify code1
    code1 = escodegen.generate code1

    jseq code1, '
      var _closure_0 = {};
      _closure_0.prefix = \'-\';
      var _flatten_x = function x(_closure, a) {
        return prefix + typeof a;
      };
      _flatten_x(_closure_0, 1);
    '

  it 'regression: allows variables to be stored elsewhere', () ->
    code1 = esprima.parse '
      function _flatten_x(_closure, a) {
        return _closure.prefix + typeof a;
      }
      function main() {
        var _closure_0 = {};
        _closure_0.prefix = \'-\';
        var y = _flatten_x;
        console.log(y(1));
        console.log(y(\'lel\'));
      }
    '

    bindify code1
    code1 = escodegen.generate code1

    jseq code1, '
      function _flatten_x(_closure, a) {
        return _closure.prefix + typeof a;
      }
      function main() {
        var _closure_0 = {};
        _closure_0.prefix = \'-\';
        var y = BIND(_flatten_x, _closure_0);
        console.log(y(1));
        console.log(y(\'lel\'));
      }
    '

describe 'depropinator', () ->
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

describe 'requireObliteratinator', () ->
  it 'turns modules into functions that return modules', () ->
    code1 = esprima.parse '
      foobarbaz();
      module.exports = 3;
    '

    requireObliteratinator(code1, { filename: '/path/to/the-module.js', isMain: false })
    code1 = escodegen.generate code1

    jseq code1, "
      var _was_module_initialised_themodule = false;
      var _module_themodule;
      function _require_themodule() {
        function _initmodule_themodule() {
          var module = {};
          var __filename = '/path/to/the-module.js';
          var __dirname = '/path/to';
          foobarbaz();
          module.exports = 3;
          return module.exports;
        }
        if (_was_module_initialised_themodule) {
          return _module_themodule;
        }
        _module_themodule = _initmodule_themodule();
        return _module_themodule;
      }
    "

  it 'reads foundModules hash to map absolute filenames to module names', () ->
    code1 = esprima.parse '
      require("foo");
      require("./foo");
      require("/path/to/foo");
    '

    requireObliteratinator(code1, {
      filename: __dirname + '/the-module.js',
      isMain: false,
      _doWrap: false,  # shortens output by removing outer func
      foundModules: {
        '/path/to/foo': '_foo'
      },
      resolve: (name) ->
        ok name in ['foo', './foo', '/path/to/foo']
        return '/path/to/foo'
    })
    code1 = escodegen.generate code1

    jseq code1, "
      _require_foo();
      _require_foo();
      _require_foo();
    "

  it 'calls readFileSync to read the module file', () ->
    code1 = esprima.parse '
      require("foo");
    '

    rfsCalled = false
    rfs = (name) ->
      ok name is '/path/to/foo'
      rfsCalled = true
      return Buffer('')
    recursed = false

    foundModules = {}

    requireObliteratinator(code1, {
      filename: __dirname + '/the-module.js',
      isMain: false,
      _doWrap: false,  # shortens output by removing outer func
      foundModules,
      resolve: (name) ->
        ok name is 'foo'
        return '/path/to/foo'
      readFileSync: rfs
      _recurse: (ast, opt) ->
        recursed = true
        ok.equal(ast.type, 'Program')
        ok.deepEqual(ast.body, [])
        ok.equal(opt.isMain, false)
        ok.equal(opt.readFileSync, rfs)
        ok.equal(opt.filename, '/path/to/foo')
        ok.equal(opt.slug, '_foo')
        ok.strictEqual(opt.foundModules, foundModules)
        return { type: 'Program', body: [] }
    })

    ok rfsCalled, 'readFileSync was called'
    ok recursed, 'function recursed into itself'

describe 'thatter', () ->
  it 'this works', () ->
    arr = []
    eval(bindifyPrelude + (dumbjs '''
      var callMe = function() { return this() }
      var add1 = function(){ return this + 1 }
      var identity = function() { return this }
      arr.push(callMe.call(function(){ return 6 }))
      arr.push([add1][0]())
      var x = { y: { zed: identity } }
      arr.push([ x, x.y.zed() ])
      var foo = function (x) {
        return this + x;
      }
      arr.push(foo.call(1, 4));
      function bar() {
        return this
      }
      arr.push(bar.call(50))
    ''') + '\nmain()')

    ok.equal(arr[0], 6)
    ok(/String\(_self\) \+ String\(1\)/.test(arr[1]), 'couldn\'t find this + 1 in ' + arr[1])
    ok(/}1$/.test(arr[1]), 'doesnt end in "1" as "+ 1" told it to: ' + arr[1])
    ok.equal(arr[2][0].y, arr[2][1])
    ok.equal(arr[3], 5)
    ok.equal(arr[4], 50)

  it 'turns functions using this into functions with an extra _self argument', () ->
    code1 = esprima.parse 'var x = function () { return this; }'

    thatter code1
    code1 = escodegen.generate code1

    jseq code1, "
      var x = function (_self) { return _self; }
    "

  it 'finds instances of Function.prototype.call', () ->
    code1 = esprima.parse "
      var x = function () { return x.call(this, 3, 4); } ;
      x.call(2, 3, 4) ;
      var y = x ;
      y.call(1)
    "

    thatter code1
    code1 = escodegen.generate code1

    jseq code1, "
      var x = function (_self) { return x(_self, 3, 4); };
      x(2, 3, 4);
      var y = x;
      y(1)
    "

  it 'regression: Works inside a main function', () ->
    code1 = esprima.parse "
      function main() {
        function x() { return someObject.x(this) };
        var someObject = { x: x };
        someObject.x(1, 2);
        someObject.y = x;
        someObject.y(4);
      }
    "

    thatter code1
    code1 = escodegen.generate code1

    jseq code1, "
      function main() {
        function x(_self) { return someObject.x(someObject, _self); } ;
        var someObject = { x: x };
        someObject.x(someObject, 1, 2);
        someObject.y = x;
        someObject.y(someObject, 4);
      }
    "

  it 'finds function being called on the object', () ->
    code1 = esprima.parse "
      function x() { return someObject.x(this) };
      var someObject = { x: x };
      someObject.x(1, 2);
      someObject.y = x;
      someObject.y(4);
    "

    thatter code1
    code1 = escodegen.generate code1

    jseq code1, "
      function x(_self) { return someObject.x(someObject, _self); } ;
      var someObject = { x: x };
      someObject.x(someObject, 1, 2);
      someObject.y = x;
      someObject.y(someObject, 4)
    "

describe 'assertions', () ->
  it 'screams at you for using globals'

  it 'screams at you for using eval, arguments, this, reserved names (_closure_, _closure, _flatten_, _ownfunction_)'

describe 'functional tests', () ->
  it 'its code runs on node', () ->
    hi = null
    eval(bindifyPrelude + dumbjs('(function(){ hi = "hi" }())') + ';main()')
    ok.equal(hi, 'hi')

  it 'require() works', () ->
    XFOO = null
    code = dumbjs 'XFOO=require("./some.js");', { filename: __filename }  # actual file in this directory
    eval(bindifyPrelude + code + '\nmain()')
    ok.equal XFOO(), 'xfoo'

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

  it 'regression: closure membex found in for() init section', () ->
    code = dumbjs('''
function a() {
  var b = function() {
    switch (0) {
      default:
        for (var i = 1;;) {
        }
    }

    (function(){ return i })();
  };
};
    ''')

    eval(bindifyPrelude + code + ';main()')

  it.skip 'requiring node core modules works', () ->
    arr = []

    code = dumbjs('''
      var util = require('util')
      arr = [ 'deepEqual' in util ]
    ''')

    fs.writeFileSync('/tmp/tmpmod.js', bindifyPrelude + code + ';main()')
    require('/tmp/tmpmod.js')

    #eval(bindifyPrelude + code + ';main()')

    ok.deepEqual(arr, [true])

  it 'regression: closures don\'t work if passed recursively through a function that doesn\'t use them', () ->
    arr = []

    eval(bindifyPrelude + dumbjs('''
      function maker(start) {
        return (function makeriife() {
          return function makerreturner() {
            return ++start
          }
        }())
      }
      arr.push(maker(7)())
    ''') + ';main()')

    ok.deepEqual(arr, [ 8 ])

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

    arr = []
    eval(bindifyPrelude + dumbjs(first_chunk + second_chunk) + ';main()')
    ok.deepEqual(
      arr,
      [-1, 0, 1]
    )

    arr = []
    eval(bindifyPrelude + dumbjs(first_chunk + 'arr.push(fib(4))') + ';main()')
    ok.equal(arr[0], 3)

