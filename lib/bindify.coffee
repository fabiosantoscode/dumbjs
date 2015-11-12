assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'

module.exports = (programNode, { bindFunctionName = 'BIND' } = {}) ->
  toWrap = []  # Array of { func, closureName }
  scopeMan = escope.analyze programNode

  currentScope = scopeMan.acquire programNode

  estraverse.traverse(programNode, {
    enter: (node, parent) ->
      if node.type in ['FunctionExpression', 'FunctionDeclaration']
        currentScope = scopeMan.acquire node

      if node.type in ['Identifier'] and
          /^_flatten_/.test(node.name) and
          parent.type isnt 'VariableDeclarator' and
          parent.type isnt 'FunctionDeclaration' and
          parent.type isnt 'FunctionExpression'
        closure = currentScope.variables.filter((p) -> /^_closure_/.test p.name)[0]
        if closure and /^_closure_/.test(closure.name) and func_needs_bind(programNode, node.name)
          toWrap.push({ func: node, closureName: closure.name })
    leave: (node) ->
      if node.type in ['FunctionExpression', 'FunctionDeclaration']
        currentScope = currentScope.upper
  })

  estraverse.replace(programNode, {
    leave: (node) ->
      for { func, closureName } in toWrap
        if func is node
          return call(bindFunctionName, [func, { type: 'Identifier', name: closureName }])
  })

call = (name, args) ->
  type: 'CallExpression',
  callee:
    type: 'Identifier',
    name: name,
  'arguments': args,

func_needs_bind = (program, funcName) ->
  return func_by_name(program, funcName).params[0]?.name is '_closure'

func_by_name = (program, needle) ->
  all_funcs(program.body).filter(({ node, name }) -> name is needle)[0].node

all_funcs = (body) ->
  return body.map(get_func_decl).filter((x) -> x isnt undefined)

get_func_decl = (node) ->
  if node.type is 'FunctionDeclaration'
    return { node: node, name: node.id.name }
  if node.type is 'VariableDeclaration' and
      node.declarations[0].init?.type is 'FunctionExpression'
    { id, init } = node.declarations[0]
    return { node: init, name: id.name }
  return undefined
