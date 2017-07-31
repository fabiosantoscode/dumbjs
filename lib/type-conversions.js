'use strict'

var assert = require('assert')

var tern = require('tern/lib/infer')
var estraverse = require('estraverse')

var util = require('./util')

module.exports = function binOps(ast, options) {
  options = options || {}
  tern.withContext(new tern.Context(), function () {
    tern.analyze(ast)
    _binOps(ast, tern.cx().topScope, options)
  })
}

function _binOps(ast, ternState, options) {
  var ternContext = tern.cx()
  estraverse.replace(ast, {
    enter: function (node) {
      if (node !== ast && /^Function/.test(node.type)) {
        _binOps(node, node.scope, options)
        return this.skip()
      }
      if (node.type === 'BinaryExpression') {
        var leftType = tern.expressionType({ node: node.left, state: ternState })
        var rightType = tern.expressionType({ node: node.right, state: ternState })

        if (leftType && leftType !== tern.ANull) { leftType = leftType.getType(false) }
        if (leftType && rightType !== tern.ANull) { rightType = rightType.getType(false) }
        if (!leftType || !rightType) { return }

        if (
          (leftType instanceof tern.Prim) &&
          (rightType instanceof tern.Prim) &&
          leftType.name === rightType.name) { return }

        if (
          node.operator === '+' &&
          (leftType === tern.ANull || rightType === tern.ANull) &&
          options.avoidJSAdd !== true
        ) {
          // Let the downstream decide how to add 2 types
          // We don't know one of them
          // So we don't know whether to convert them to string or not

          // When avoidJSAdd is true, we just wing it and assume unknown types are numbers.
          return util.call('JS_ADD', [ node.left, node.right ])
        }
        if (node.operator === '+' &&
            (convertsToStringWhenAdding(leftType) || convertsToStringWhenAdding(rightType))
        ) {
          // https://tc39.github.io/ecma262/#sec-addition-operator-plus-runtime-semantics-evaluation
          // 7. If Type(lprim) is String or Type(rprim) is String, then
          if (leftType.name !== 'string') {
            //   a. Let lstr be ? ToString(lprim).
            node.left = util.call('String', [node.left])
          }
          if (rightType.name !== 'string') {
            //   b. Let rstr be ? ToString(rprim).
            node.right = util.call('String', [node.right])
          }
          //   c. Return the String that is the result of concatenating lstr and rstr.
          return node
        } else {
          return {
            type: 'BinaryExpression',
            operator: node.operator,
            left: leftType.name !== 'number' ? util.call('Number', [ node.left ]) : node.left,
            right: rightType.name !== 'number' ? util.call('Number', [ node.right ]) : node.right,
          }
        }
      }
      if (node.type === 'UnaryExpression') {
        if (node.operator === '-') {
          return {
            type: 'UnaryExpression',
            operator: node.operator,
            argument: util.call('Number', [node.argument]),
            prefix: node.prefix,
          }
        }
        if (node.operator === '+') {
          return util.call('Number', [node.argument])
        }
      }
    }
  })
}

function convertsToStringWhenAdding(type) {
  return type.name === 'string' ||
    (type instanceof tern.Fn) ||
    (type instanceof tern.Obj) ||
    (type instanceof tern.Arr)
}
