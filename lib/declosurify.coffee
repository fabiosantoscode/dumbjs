assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'
tern = require 'tern/lib/infer'

# Every function that has an execution environment will save their shit in a _closure
# variable.

module.exports = (programNode) ->
  tern.withContext(new tern.Context(), () -> _declosurify(programNode))

_declosurify = (programNode) ->
  tern.analyze(programNode)

  scope_stack = []  # From outermost to innermost, the lexical scopes
  current_scope = () -> scope_stack[scope_stack.length - 1]
  _counter = 0
  closure_name = () -> "_closure_#{_counter++}"

  scope_with = (name) ->
    assert typeof name is 'string'
    i = scope_stack.length
    while i--
      if scope_stack[i].props[name]
        return scope_stack[i]

  to_unshift = []  # We keep notes of { func, scopeName } so we add var _closure_X = {} later.

  estraverse.replace programNode,
    enter: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        assert node.scope
        node.scope.name = closure_name()
        scope_stack.push node.scope
        to_unshift.push({ func: node, scopeName: node.scope.name })
      return node
    leave: (node, parent) ->
      if current_scope() is node.scope
        scope_stack.pop()

      if node.type in ['Identifier'] and
          current_scope() and
          scope_with(node.name) and
          not /Function/.test parent.type
        return member_expr(scope_with(node.name).name, node.name)

      if node.type is 'BlockStatement'
        node.closure = null
        bod = []
        for _node in node.body
          if _node.type is 'VariableDeclaration'
            for decl in _node.declarations
              init = decl.init or { type: 'Identifier', name: 'undefined' }
              bod.push assignment(decl.id, init)
          else
            bod.push(_node)
        return { type: 'BlockStatement', body: bod }

      return node

  for { func, scopeName } in to_unshift
    func.body.body.unshift object_decl(scopeName)

object_decl = (name) ->
  type: "VariableDeclaration",
  kind: "var"
  declarations: [
    type: "VariableDeclarator",
    id:
      type: "Identifier",
      name: name
    init:
      type: "ObjectExpression",
      properties: []
  ],

member_expr = (left, right) ->
  type: "MemberExpression",
  computed: false,
  object:
    type: "Identifier",
    name: left,
  property:
    type: "Identifier",
    name: right,

assignment = (left, right) ->
  type: "ExpressionStatement",
  expression:
    type: "AssignmentExpression",
    operator: '=',
    left: left,
    right: right,
