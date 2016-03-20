'use strict'

var tern = require('tern/lib/infer')
var estraverse = require('estraverse')
var assert = require('assert')

module.exports = function (ast) {
  var toReplace = thatter(ast)
  replaceCalls(ast, toReplace)
}

function thatter(ast) {
  var usesThis = false;
  var out = [];
  estraverse.replace(ast, {
    enter: function (node) {
      if (node === ast) { return; }
      if (/^Function/.test(node.type)) {
        out = out.concat(thatter(node));
        return this.skip();
      }
      if (node.type === 'ThisExpression' && ast.type !== 'Program') {
        usesThis = true;
        return { type: 'Identifier', name: '_self' }
      }
    }
  })

  if (usesThis) {
    ast.params.unshift({ type: 'Identifier', name: '_self' })
    var functionNode = ast;
    out = out.concat([ functionNode ])
  }

  return out
}

function replaceCalls(ast, toReplace) {
  var cx = new tern.Context();
  tern.withContext(cx, function () {
    tern.analyze(ast, '-', cx.topScope)
    var scope = cx.topScope
    estraverse.replace(ast, {
      enter: function (node) {
        if (node === ast) { return }
        if (/^Function/.test(node.type)) {
          scope = node.scope;
        }
      },
      leave: function (node) {
        if (/^Function/.test(node.type)) {
          scope = node.scope;
        }
        if (
          node.type === 'CallExpression' &&
          node.callee.type === 'MemberExpression' &&
          node.callee.property.type === 'Identifier' &&
          node.callee.property.name === 'call'
        ) {
          var functionType = tern.expressionType({ node: node.callee.object, state: scope }).getFunctionType()
          if (functionType && toReplace.indexOf(functionType.originNode) !== -1) {
            return {
              type: 'CallExpression',
              callee: node.callee.object,
              arguments: node.arguments,
            }
          }
        } else if (
          node.type === 'CallExpression' &&
          node.callee.type === 'MemberExpression'
        ) {
          var functionType = tern.expressionType({ node: node.callee, state: scope }).getFunctionType()
          if (functionType && toReplace.indexOf(functionType.originNode) !== -1) {
            if (!guaranteedNoSideEffects(node.callee))
              return makeCallerIIFE(node.callee, node.arguments)
            return {
              type: 'CallExpression',
              callee: deepClone(node.callee),
              arguments: [node.callee.object].concat(node.arguments)
            }
          }
        }
      }
    })
  })
}

function deepClone(object) {
  return JSON.parse(JSON.stringify(object))
}

function guaranteedNoSideEffects(node) {
  if (node.type == 'Identifier') return true;
  if (node.type == 'MemberExpression' && !node.computed) return guaranteedNoSideEffects(node.object);
  return false;
}

function makeCallerIIFE(membex, callArguments) {
  return {
    type: 'CallExpression',
    callee: {
      type: 'FunctionExpression',
      id: { type: 'Identifier', name: 'selfCallerIIFE' },
      params: [ { type: 'Identifier', name: 'callee' } ],
      body: {
        type: 'BlockStatement',
        body: [{
          type: 'ReturnStatement',
          argument: {
            type: 'CallExpression',
            callee: {
              type: 'MemberExpression',
              computed: membex.computed,
              object: { type: 'Identifier', name: 'callee' },
              property: membex.property,
            },
            arguments: [{type: 'Identifier', name: 'callee'}].concat(callArguments),
          },
        }]
      },
    },
    arguments: [ membex.object ],
  }
}
