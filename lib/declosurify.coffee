assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'
tern = require 'tern/lib/infer'

# Every function that has an execution environment will save their shit in a _closure
# variable.

module.exports = (args...) ->
  tern.withContext(new tern.Context(), () -> _declosurify(args...))

_declosurify = (programNode, opt = {}) ->
  tern.analyze(programNode)

  scope_stack = []  # From outermost to innermost, the lexical scopes
  current_scope = () -> scope_stack[scope_stack.length - 1]
  upper_scope = () -> scope_stack[scope_stack.length - 2]
  _counter = 0
  closure_name = () -> "_closure_#{_counter++}"

  scope_with = (name) ->
    assert typeof name is 'string'
    i = scope_stack.length
    while i--
      { props, fnType, originNode } = scope_stack[i]
      if props[name] or (name in fnType.argNames)
        return scope_stack[i]

      if name in functions_declared(scope_stack[i].originNode)
        return scope_stack[i]

  functions_declared = (functionNode) ->
    if opt.funcs is false
      return []
    funcs = []
    # Look for function declarations with the given name.
    # For some reason tern doesn't give me this?
    estraverse.traverse(functionNode, {
      enter: (node) ->
        if node is functionNode
          return
        if node.type is 'FunctionDeclaration' and node.id
          funcs.push node.id.name
        if /Function/.test(node.type)
          return @skip()
    })
    return funcs

  scopes_above = () ->
    return scope_stack.slice(0).reverse().slice(1).map(Object.freeze)

  to_unshift = []  # We keep notes of { func, closureName, scopesAbove } so we add var _closure_X = {} later.

  estraverse.replace programNode,
    enter: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        assert node.scope
        node.scope.name = closure_name()
        scope_stack.push node.scope
        to_unshift.push({
          func: node,
          closureName: node.scope.name,
          scopesAbove: scopes_above(),
        })

        if parent isnt programNode and
            opt.recursiveClosures isnt false
          node.params.unshift({ type: 'Identifier', name: '_closure' })
      return node
    leave: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        scope_stack.pop()

      if node.type in ['Identifier'] and
          current_scope() and
          not /Function/.test parent.type
        identScope = scope_with(node.name)
        if identScope
          lookInClosuresArgument = (opt.recursiveClosures isnt false) and
            (current_scope() isnt identScope)
          if lookInClosuresArgument and upper_scope() is identScope
            # The closure is the outer closure, which was passed as the "_closure" argument
            return member_expr('_closure', node.name)
          else if lookInClosuresArgument and upper_scope() isnt identScope
            # The closure is out of the upper closure
            return member_expr(
              member_expr('_closure', identScope.name),
              node.name)
          else
            return member_expr(identScope.name, node.name)

      if node.type is 'BlockStatement'
        node.closure = null
        bod = []
        if parent.type in ['FunctionDeclaration', 'FunctionExpression']
          if opt.params != false
            for param in parent.params
              if param.name isnt '_closure'
                bod.push assignment(
                  member_expr(scope_with(param.name).name, param.name),
                  param)
          if opt.fname != false
            for funct in functions_declared(node)
              bod.push assignment(
                member_expr(current_scope().name, funct),
                funct)
        for _node in node.body
          if _node.type is 'VariableDeclaration'
            for decl in _node.declarations
              init = decl.init or 'undefined'
              bod.push assignment(decl.id, init)
          else if _node.type is 'ForStatement' and _node.init.type is 'VariableDeclaration'
            for decl in _node.init.declarations
              bod.push assignment(decl.id, decl.init or 'undefined')
            _node.init = null
            bod.push(_node)
          else
            bod.push(_node)
        return { type: 'BlockStatement', body: bod }

      return node

  for { func, closureName, scopesAbove } in to_unshift
    if opt.recursiveClosures isnt false and
        scopesAbove.length isnt 0
      [upperClosure, otherClosures...] = scopesAbove
      otherClosures.reverse()  # just so the the assignments are in a prettier order

      for closure in otherClosures
        func.body.body.unshift(
          assignment(
            member_expr(closureName, closure.name),
            member_expr('_closure', closure.name)))
      func.body.body.unshift(
        assignment(
          member_expr(closureName, upperClosure.name),
          '_closure'))
    func.body.body.unshift object_decl(closureName)

object_decl = (name) ->
  type: "VariableDeclaration",
  kind: "var"
  declarations: [
    type: "VariableDeclarator",
    id: identIfString(name),
    init:
      type: "ObjectExpression",
      properties: []
  ],

identIfString = (ast) ->
  if typeof ast is 'string'
    return { type: 'Identifier', name: ast }
  return ast

member_expr = (left, right) ->
  type: "MemberExpression",
  computed: false,
  object: identIfString(left),
  property: identIfString(right),

assignment = (left, right) ->
  type: "ExpressionStatement",
  expression:
    type: "AssignmentExpression",
    operator: '=',
    left: identIfString(left),
    right: identIfString(right),
