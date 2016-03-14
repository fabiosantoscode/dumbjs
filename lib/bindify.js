'use strict'

var assert = require('assert')
var escope = require('escope')
var estraverse = require('estraverse')

module.exports = function (programNode, options) {
  var bindFunctionName = (options && options.bindFunctionName) || 'BIND'
  var toWrap = []  // Array of { func, closureName }
  var scopeMan = escope.analyze(programNode)
  var scopeStack = [ scopeMan.acquire(programNode) ]  // From outermost to innermost, the lexical scopes
  var currentScope = function () { return scopeStack[scopeStack.length - 1] }

  estraverse.traverse(programNode, {
    enter: function (node, parent) {
      if (/^Function/.test(node.type)) {
        var scope = scopeMan.acquire(node)
        if (scope.type === 'function-expression-name') {
          scope = scope.childScopes[0]
        }
        scopeStack.push(scope)
        return
      }
      if (node.type === 'Identifier' &&
          /^_flatten_/.test(node.name) &&
          !/^VariableDeclarator|^Function/.test(parent.type)) {
        var closure = currentScope().variables.filter(function (p) { return /^_closure_/.test(p.name) })[0]
        if (closure && funcNeedsBind(programNode, node.name)) {
          toWrap.push({ func: node, closureName: closure.name })
        }
      }
    },
    leave: function (node) {
      if (/^Function/.test(node.type)) {
        scopeStack.pop()
      }
    }
  })

  estraverse.replace(programNode, {
    leave: function (node) {
      for (var i = 0; i < toWrap.length; i++) {
        var closureName = toWrap[i].closureName;
        var func = toWrap[i].func;
        if (func === node) {
          return call(bindFunctionName, [func, { type: 'Identifier', name: closureName }])
        }
      }
    }
  })
}

function call(name, args) {
  return {
    type: 'CallExpression',
    callee: {
      type: 'Identifier',
      name: name,
    },
    arguments: args,
  }
}

function funcNeedsBind(program, funcName) {
  var firstParam = funcByName(program, funcName).params[0]
  return firstParam && firstParam.name === '_closure'
}

function funcByName(program, needle) {
  return allFuncs(program.body)
    .filter(function (nodeAndName) { return nodeAndName.name === needle })
    [0].node
}

function allFuncs(body) {
  return body.map(getFuncDecl)
    .filter(function (x) { return x !== undefined })
}

function getFuncDecl(node) {
  if (node.type === 'FunctionDeclaration') {
    return { node: node, name: node.id.name }
  }
  if (node.type === 'VariableDeclaration' &&
      node.declarations[0].init &&
      node.declarations[0].init.type === 'FunctionExpression') {
    return { node: node.declarations[0].init, name: node.declarations[0].id.name }
  }
  return undefined
}

