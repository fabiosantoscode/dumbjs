fs = require 'fs'
assert = require 'assert'
escope = require 'escope'
esprima = require 'esprima'
escodegen = require 'escodegen'
estraverse = require 'estraverse'
child_process = require 'child_process'

requireObliteratinator = require './require-obliteratinator'
topmost = require './topmost'
declosurify = require './declosurify'
bindify = require './bindify'
mainify = require './mainify'
thatter = require './thatter'
depropinator = require './depropinator'
ownfunction = require './ownfunction'

clean_ast = (ast) ->
  estraverse.traverse(ast, {
    leave: (node) ->
      delete node.scope
      delete node.objType
  })

dumbifyAST = (ast, opt = {}) ->
  if opt.requireObliteratinator isnt false
    ast = requireObliteratinator ast
    clean_ast ast
  if opt.mainify isnt false
    mainify(ast, opt.mainify or {})
    clean_ast ast
  if opt.thatter isnt false
    thatter ast
    clean_ast ast
  if opt.depropinator isnt false
    depropinator ast
    clean_ast ast
  if opt.declosurify isnt false  # this one is not really a pass, it's a pre-declosurify operation
    ownfunction ast
    clean_ast ast
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
    else if node.type in ['Program', 'BlockStatement']
      declarations_to_declarators = (decls, kind) ->
        return decls.map (decl) -> {
          type: 'VariableDeclaration',
          declarations: [ decl ],
          kind: kind,
        }
      node.body = node.body
        .map (node) ->
          if node.type is 'VariableDeclaration' and node.declarations.length isnt 1
            return declarations_to_declarators(node.declarations, node.kind)
          if node.type is 'ForStatement' and node.init?.type is 'VariableDeclaration' and node.init.declarations.length isnt 1
            init = node.init;
            node.init = null;
            return declarations_to_declarators(init.declarations, init.kind).concat([node])
          else
            return [node]
        .reduce(
          (accum, b) -> accum.concat(b),
          []
        )
      return node
    else if node.type in ['Program', 'Identifier', 'CallExpression', 'BlockStatement', 'FunctionExpression', 'VariableDeclaration', 'VariableDeclarator', 'IfStatement', 'UnaryExpression', 'MemberExpression', 'LogicalExpression', 'BinaryExpression', 'ReturnStatement', 'NewExpression', 'ThrowStatement', 'SequenceExpression', 'AssignmentExpression', 'ObjectExpression', 'Property', 'ConditionalExpression', 'ForStatement', 'UpdateExpression', 'ArrayExpression', 'ThisExpression', 'SwitchStatement', 'SwitchCase', 'BreakStatement', 'WhileStatement', 'EmptyStatement']
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

dumbify = (js, opt = {}) ->
  mayContainRequire = /require\s*?\(/m.test js
  ast = esprima.parse(js, acornOpts)
  if mayContainRequire is false
    opt.requireObliteratinator = false
  ast = dumbifyAST ast, opt
  return escodegen.generate ast

module.exports = dumbify
module.exports.dumbify = dumbify
module.exports.dumbifyAST = dumbifyAST
