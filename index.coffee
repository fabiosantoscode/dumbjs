fs = require 'fs'
assert = require 'assert'
escope = require 'escope'
esprima = require 'esprima'
escodegen = require 'escodegen'
estraverse = require 'estraverse'
child_process = require 'child_process'

topmost = require './lib/topmost'
declosurify = require './lib/declosurify'
bindify = require './lib/bindify'
mainify = require './lib/mainify'
depropinator = require './lib/depropinator'
ownfunction = require './lib/ownfunction'

clean_ast = (ast) ->
  estraverse.traverse(ast, {
    leave: (node) ->
      delete node.scope
      delete node.objType
  })

dumbifyAST = (ast, opt = {}) ->
  if opt.mainify isnt false
    mainify ast
    clean_ast ast
  if opt.depropinator isnt false
    depropinator ast
    clean_ast ast
  if opt.declosurify isnt false  # this one is not really a pass, it's a pre-declosurify operation
    ownfunction ast
    clean_ast ast
  if opt.declosurify isnt false
    declosurify ast
    clean_ast ast
  if opt.topmost isnt false
    topmost ast
    clean_ast ast
  if opt.bindify isnt false
    bindify ast  # mutate ast
    clean_ast ast
  return estraverse.replace ast, enter: (node) ->
    if node.type is 'ExpressionStatement'
      if node.expression.type is 'Literal'
        return estraverse.VisitorOption.Remove
      return node  # TODO check what we get first
    else if node.type in ['FunctionDeclaration']
      node.type = 'FunctionExpression'
      name = node.id.name
      node.id = null
      return {
        "type": "VariableDeclaration",
        "declarations": [
          {
            "type": "VariableDeclarator",
            "id": {
              "type": "Identifier",
              "name": name
            },
            "init": node
          }
        ],
        "kind": "var"
      }
      node.type = 'FunctionExpression'
      return node
    else if node.type is 'Literal'
      if node.regex
        assert false, 'using regexps is currently not allowed in dumbscript'
    else if node.type in ['Program', 'Identifier', 'CallExpression', 'BlockStatement', 'FunctionExpression', 'VariableDeclaration', 'VariableDeclarator', 'IfStatement', 'UnaryExpression', 'MemberExpression', 'LogicalExpression', 'BinaryExpression', 'ReturnStatement', 'NewExpression', 'ThrowStatement', 'SequenceExpression', 'AssignmentExpression', 'ObjectExpression', 'Property', 'ConditionalExpression', 'ForStatement', 'UpdateExpression', 'ArrayExpression', 'ThisExpression', 'SwitchStatement', 'SwitchCase', 'BreakStatement', 'WhileStatement']
      return node
    else
      throw new Error('Unknown node type ' + node.type + ' in ' + node)

acornOpts = {
  sourceType: 'module',
  ecmaVersion: 6,
  allowReturnOutsideFunction: true,
  allowHashBang: true,
  locations: true
}

flatten = (js) ->
  return js unless /require\s*?\(/m.test js
  ret = child_process.spawnSync('node', [__dirname + '/bin/flatten.js'], { input: js })
  if ret.status isnt 0 || ret.error
    throw ret.error || new Error(ret.stderr+'')
  return ret.stdout+''

dumbify = (js, opt = {}) ->
  js = flatten js
  ast = esprima.parse(js, acornOpts)
  ast = dumbifyAST ast, opt
  return escodegen.generate ast

module.exports = dumbify
module.exports.dumbify = dumbify
module.exports.dumbifyAST = dumbifyAST
module.exports.flatten = flatten
