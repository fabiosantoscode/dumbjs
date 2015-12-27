assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'
tern = require 'tern/lib/infer'

# Every function that has an execution environment will save their shit in a _closure
# variable.

module.exports = (args...) ->
  tern.withContext(new tern.Context(), () -> _declosurify(args...))

_declosurify = (programNode, opt = {}) ->
  scopeMan = escope.analyze programNode
  escope_scope = scopeMan.acquire(programNode)
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

  current_function = () -> scope_stack[scope_stack.length - 1].originNode

  scopes_above = () ->
    return scope_stack.slice(0).reverse().slice(1).map(Object.freeze)

  to_unshift = []  # We keep notes of { func, closureName, scopesAbove } so we add var _closure_X = {} later.

  this_function_needs_to_pass_closure = () ->
    if opt.always_create_closures
      return true
    for variable in escope_scope.variables
      if variable.stack is false
        return true
    for through in escope_scope.through
      if through.resolved and
          is_above(current_scope, through.resolved.scope)
        return true
    return false

  this_function_needs_to_take_closure = () ->
    if opt.always_create_closures
      return true
    do_log = current_function().id?.name is 'immuneToPassing'
    if do_log
      x = escope_scope.references.filter((x) -> x.resolved?.name is 'x')[0]
    for ref in escope_scope.references
      if ref.resolved and
          ref.resolved.stack isnt true and
          is_above(ref.resolved.scope, escope_scope)
        return true
    for through in escope_scope.through
      if through.resolved
        return true
    return false

  ident_to_member_expr = (node) ->
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
      else if identScope.name
        return member_expr(identScope.name, node.name)

  estraverse.replace programNode,
    enter: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        escope_scope = scopeMan.acquire(node)
        scope_stack.push node.scope
        assert node.scope

        if this_function_needs_to_pass_closure()
          node.scope.name = closure_name()
          to_unshift.push({
            func: node,
            closureName: node.scope.name,
            scopesAbove: scopes_above(),
          })

        if this_function_needs_to_take_closure()
          if parent isnt programNode and
              opt.recursiveClosures isnt false
            node.params.unshift({ type: 'Identifier', name: '_closure' })
      return node
    leave: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        escope_scope = escope_scope.upper
        if escope_scope?.type is 'function-expression-name'
          escope_scope = escope_scope.upper
        scope_stack.pop()
        return

      if global?.it and scope_stack.length
        # a dumb but effective way to test these functions
        if current_function().id?.name is 'immuneToGetting'
          assert(this_function_needs_to_pass_closure(), '1')
          assert(!this_function_needs_to_take_closure(), '2')
        if current_function().id?.name is 'immuneToPassing'
          assert(!this_function_needs_to_pass_closure(), '3')
          assert(this_function_needs_to_take_closure(), '4')
        if current_function().id?.name is 'dontPassMe'
          assert(!this_function_needs_to_pass_closure(), '5')
          assert(!this_function_needs_to_take_closure(), '6')

      if node.type in ['Identifier'] and
          current_scope() and
          not /Function/.test(parent.type) and
          # parent.type isnt 'VariableDeclarator' and
          (this_function_needs_to_take_closure() or this_function_needs_to_pass_closure())
        return ident_to_member_expr(node)

      if node.type is 'BlockStatement' and
          this_function_needs_to_pass_closure()
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
          else if _node.type is 'ForStatement' and _node.init?.type is 'VariableDeclaration'
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
        scopesAbove.length isnt 0 and
        func.params[0]?.name is '_closure'
      [upperClosure, otherClosures...] = scopesAbove
      otherClosures.reverse()  # just so the the assignments are in a prettier order

      for closure in otherClosures
        if closure.name
          func.body.body.unshift(
            assignment(
              member_expr(closureName, closure.name),
              member_expr('_closure', closure.name)))
      if upperClosure.name
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
  assert left, 'member_expr: left is ' + left
  assert right, 'member_expr: right is ' + right
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

is_above = (above, scope) ->
  assert scope, 'scope is ' + scope
  assert above, 'above is ' + above
  assert scope.upper isnt undefined, 'scope is not a scope, its .upper is ' + scope.upper
  assert above.upper isnt undefined, 'above is not a scope, its .upper is ' + above.upper
  while scope
    scope = scope.upper
    if scope is above
      return true
  return false
