assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'

module.exports = (programNode, { bindFunctionName = 'BIND' } = {}) ->
  toWrap = []  # Array of { func, closureName }
  scopeMan = escope.analyze programNode
  scope_stack = [ scopeMan.acquire(programNode) ]  # From outermost to innermost, the lexical scopes
  current_scope = () -> scope_stack[scope_stack.length - 1]

  estraverse.traverse(programNode, {
    enter: (node, parent) ->
      if node.type in ['FunctionExpression', 'FunctionDeclaration']
        scope = scopeMan.acquire node
        if scope.type is 'function-expression-name'
          scope = scope.childScopes[0]
        scope_stack.push scope
        return

      if node.type in ['Identifier'] and
          /^_flatten_/.test(node.name) and
          parent.type not in ['VariableDeclarator', 'FunctionDeclaration', 'FunctionExpression']
        closure = current_scope().variables.filter((p) -> /^_closure_/.test p.name)[0]
        if closure and func_needs_bind(programNode, node.name)
          toWrap.push({ func: node, closureName: closure.name })
    leave: (node) ->
      if node.type in ['FunctionExpression', 'FunctionDeclaration']
        scope_stack.pop()
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
