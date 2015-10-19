assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'
tern = require 'tern/lib/infer'

module.exports = (programNode, rest...) ->
  tern.withContext(new tern.Context(), () -> _bindify(programNode))

_bindify = (programNode, { bindFunctionName = 'BIND' } = {}) ->
  tern.analyze(programNode)

  closure_stack = []
  to_wrap = []  # Array of { func, closureName }

  estraverse.replace programNode,
    enter: (node) ->
      if node.type in ['FunctionStatement', 'FunctionDeclaration']
        closure_stack.push tern.scopeAt(node)
      return
    leave: (node, parent) ->
      if node.type in ['FunctionStatement', 'FunctionDeclaration']
        closure_stack.pop tern.scopeAt(node)
        return

      if node.type in ['Identifier'] and
          /^_flatten_/.test node.name
        variables = Object.keys(closure_stack[closure_stack.length - 1].props)
        closure = variables.filter((p) -> /^_closure_/.test p)[0]
        if closure
          return call(bindFunctionName, [node, { type: 'Identifier', name: closure }])

call = (name, args) ->
  type: 'CallExpression',
  callee:
    type: 'Identifier',
    name: name,
  'arguments': args,

