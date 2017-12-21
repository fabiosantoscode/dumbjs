'use strict'

const assert = require('assert')
const { inspect } = require('util')

const checkAST = require('../../vendor/js-ast-validator/check-ast')
const esprima = require('esprima')

const util = module.exports

util.ensure = function ensure(kind, value) {
  assert(value, 'Didnt ensure value ' + inspect(value))
  assert(value.type, 'Value ' + inspect(value) + ' does not have a type property')
  assert(value.type in esprima.Syntax, 'Value ' + inspect(value) + ' does not have a valid type')
  try {
    checkAST(value, kind)
  } catch (e) {
    e.message = `Invalid AST node in ${inspect(value)} ${e.message}`
    throw e
  }
  return value
}

var ensure

util.enableTestMode = (enable = true) => {
  ensure = enable ?
    util.ensure :
    (_, x) => x
}

util.enableTestMode(false)

util.functionExpression = ({
  body,
  bodyExpr,
  id,
  params = [],
  defaults = [],
  generator = false,
  expression = false,
}) => ensure('expression', {
  type: 'FunctionExpression',
  id: id ? util.identifierIfString(id) : null,
  params: params.map(util.identifierIfString),
  defaults,
  generator,
  expression,
  body: (
    body     ? util.block(body) :
    bodyExpr ? util.block(util.return(bodyExpr)) :
               assert(false, 'pass body or bodyExpr to util.function*')
  ),
})
util.functionDeclaration = funExprArgs => {
  const expr = util.functionExpression(funExprArgs)
  expr.type = 'FunctionDeclaration'
  return ensure('statement', expr)
}
util.iifeWithArguments = (args, func) => {
  const params = Object.keys(args)
  const argumentValues = params.map(k => args[k])

  return util.iife(Object.assign({ params }, func), argumentValues)
}
util.iife = (func, args) => {
  if (!('body' in func) && !('bodyExpr' in func)) {
    // "func" is an array or other type of expression to return
    return util.iife({ body: func }, args)
  }
  return ensure('expression', util.call(
    util.functionExpression(func),
    args
  ))
}
util.call = (callee, args = []) => ensure('expression', {
  type: 'CallExpression',
  callee: util.identifierIfString(callee),
  arguments: args.map(util.identifierIfString),
})
util.new = (callee, args = []) => ensure('expression', {
  type: 'NewExpression',
  callee: util.identifierIfString(callee),
  arguments: args,
})
util.declaration = (name, init) => ensure('statement', {
  type: 'VariableDeclaration',
  kind: 'var',
  declarations: [
    { type: 'VariableDeclarator', id: util.identifierIfString(name), init: util.identifierIfString(init) }
  ]
})
util.return = argument => ensure('statement', {
  type: 'ReturnStatement',
  argument: util.identifierIfString(argument)
})
util.identifierIfString = string => {
  if (typeof string === 'string') {
    return util.identifier(string)
  }
  if (string && string.type === 'Identifier') {
    return util.identifier(string.name)
  }
  return string
}
util.block = body => ensure('statement', { type: 'BlockStatement', body: [].concat(body) })
util.if = (test, consequent, alternate = null) => ensure('statement', {
  type: 'IfStatement',
  test,
  consequent: util.block(consequent),
  alternate: alternate && util.block(alternate)
})
util.identifier = name => ensure('expression', { type: 'Identifier', name })
util.expressionStatement = (expression) => ensure('statement', {
  type: "ExpressionStatement",
  expression
})
util.assignment = (left, right) => ensure('expression', {
  type: "AssignmentExpression",
  operator: '=',
  left: util.identifierIfString(left),
  right: util.identifierIfString(right),
})
util.member = (object, property, computed = false) => ensure('expression', {
  type: 'MemberExpression',
  computed,
  object: util.identifierIfString(object),
  property: util.identifierIfString(property),
})
util.property = (key, value, computed = false) => ({
  type: 'Property',
  key: util.identifierIfString(key),
  value: util.identifierIfString(value),
  kind: 'init',
  computed
})
util.object = (properties = {}) => ensure('expression', {
  type: 'ObjectExpression',
  properties: Object.keys(properties)
    .map((prop) => {
      return util.property(prop, properties[prop])
    }),
})
util.literal = (value) => ensure('expression', { type: 'Literal', value })
util.leadingBlockComment = (node, comments) => {
  node.leadingComments = node.leadingComments || []
  node.leadingComments.push({
    type: 'Block',
    value: comments
  })
  return node
}
