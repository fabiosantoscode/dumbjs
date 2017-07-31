assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'
tern = require 'tern/lib/infer'
util = require './util'

# Every function that has an execution environment will save their shit in a _closure
# variable.

module.exports = () ->
  args = [].slice.call(arguments)
  tern.withContext(new tern.Context(), () ->
    return _declosurify.apply(null, args)
  )

_declosurify = (programNode, opt = {}) ->
  scopeMan = escope.analyze programNode
  tern.analyze(programNode)

  scope_stack = []  # From outermost to innermost, the lexical scopes
  escope_scope_stack = [ scopeMan.acquire(programNode) ]
  escope_scope = () ->
    return escope_scope_stack[escope_scope_stack.length - 1]
  current_scope = () ->
    return scope_stack[scope_stack.length - 1]
  upper_scope = () ->
    return scope_stack[scope_stack.length - 2]

  _counter = 0
  closure_name = () ->
    return "_closure_#{_counter++}"

  _counter_for_in = 0
  for_in_name = () ->
    return "_for_in_#{_counter_for_in++}"

  scope_of_function = (node) ->
    scope = scopeMan.acquire(node)
    if scope.type is 'function-expression-name'
      scope = scope.childScopes[0]
    return scope

  scope_with = (name) ->
    assert typeof name is 'string'
    i = scope_stack.length
    while i--
      if scope_has_name(scope_stack[i], name)
        return scope_stack[i]

  scope_has_name = (scope, name) ->
    return !!(scope.props[name] || (name in scope.fnType.argNames) || name in functions_declared(scope.originNode))

  scope_below_using = (scope, name, _is_first = true) ->
    if not _is_first
      was_declared = scope.variables.some((variable) -> variable.name is name)
      if was_declared  # the name was declared here, so
        return false   # we can say this scope doesn't use the outside name
      was_used = scope.references.some((ref) -> ref.identifier.name is name)
      if was_used
        return true
    return scope.childScopes.some((s) -> scope_below_using(s, name, false))

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
        if node.type is 'FunctionDeclaration' && node.id
          funcs.push node.id.name
        if /Function/.test(node.type)
          return @skip()
    })
    return funcs

  current_function = () -> scope_stack[scope_stack.length - 1].originNode

  chain_of_scopes_using_upper_closure = (_from) ->
    _from = _from || 2
    tern_scope = scope_stack[scope_stack.length - _from]
    # TODO below line works works but depends on mutable state.
    uses_upper_closure = tern_scope && tern_scope.originNode.params[0]?.name is '_closure'
    if uses_upper_closure
      return [tern_scope].concat(chain_of_scopes_using_upper_closure(_from + 1))
    if tern_scope
      return [tern_scope]
    return []

  to_unshift = []  # We keep notes of { func, closureName, scopesAbove } so we add var _closure_X = {} later.

  all_functions_below = (func) ->
    funcs = []
    estraverse.traverse(func, {
      enter: (node) ->
        if node is func
          return
        if node.type in ['FunctionDeclaration', 'FunctionExpression']
          funcs.push node
    })
    return funcs

  this_function_needs_to_pass_closure = () ->
    if opt.always_create_closures
      return true
    for variable in escope_scope().variables
      if variable.stack is false
        return true
    if /Function/.test(escope_scope().block?.type)
      funcs_below = all_functions_below(escope_scope().block)
      if funcs_below.length
        throughs = escope_scope().through.map((through) -> through.resolved)
        return funcs_below
          .map((node) -> scope_of_function node)
          .some((scope) ->
            scope.through.some((through) ->
              through.resolved isnt null and through.resolved in throughs)
          )
    return false

  this_function_needs_to_take_closure = () ->
    if opt.always_create_closures
      return true
    for ref in escope_scope().references
      if ref.resolved &&
          ref.resolved.stack isnt true &&
          is_above(ref.resolved.scope, escope_scope())
        return true
    for through in escope_scope().through
      if through.resolved
        return true
    return false

  ident_to_member_expr = (node) ->
    identScope = scope_with(node.name)
    if identScope
      lookInClosuresArgument = (opt.recursiveClosures isnt false) &&
        (current_scope() isnt identScope)
      if lookInClosuresArgument && upper_scope() is identScope
        # The closure is the outer closure, which was passed as the "_closure" argument
        return util.member('_closure', node.name)
      else if lookInClosuresArgument && upper_scope() isnt identScope
        # The closure is out of the upper closure
        return util.member(
          util.member('_closure', identScope.name),
          node.name)
      else if identScope.name
        return util.member(identScope.name, node.name)

  estraverse.replace programNode,
    enter: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        escope_scope_stack.push(scope_of_function(node))
        scope_stack.push node.scope
        assert node.scope

        if this_function_needs_to_pass_closure()
          node.scope.name = closure_name()
          to_unshift.push({
            func: node,
            closureName: node.scope.name,
            scopesAbove: chain_of_scopes_using_upper_closure(),
          })

        if this_function_needs_to_take_closure()
          if parent isnt programNode &&
              opt.recursiveClosures isnt false
            node.params.unshift(util.identifier('_closure'))

      return node
    leave: (node, parent) ->
      if node.type in ['FunctionDeclaration', 'FunctionExpression']
        escope_scope_stack.pop()
        scope_stack.pop()
        return

      if global?.it && scope_stack.length
        # a dumb but effective way to test these functions
        if current_function().id?.name is 'immuneToGetting'
          assert(this_function_needs_to_pass_closure(), '1')
          assert(!this_function_needs_to_take_closure(), '2')
        if current_function().id?.name is 'immuneToPassing'
          assert(!this_function_needs_to_pass_closure(), '3')
          assert(this_function_needs_to_take_closure(), '4')
        if current_function().id?.name is 'maker'
          assert(this_function_needs_to_pass_closure(), '7')
          assert(!this_function_needs_to_take_closure(), '8')
        if current_function().id?.name is 'makeriife'
          assert(this_function_needs_to_pass_closure(), '9')
          assert(this_function_needs_to_take_closure(), '10')
        if current_function().id?.name is 'makerreturner'
          assert(!this_function_needs_to_pass_closure(), '11')
          assert(this_function_needs_to_take_closure(), '12')
        if current_function().id?.name is 'passClosureThrough'
          assert(this_function_needs_to_pass_closure(), '13')
          assert(this_function_needs_to_take_closure(), '14')
        if current_function().id?.name is 'passMe'
          assert(!this_function_needs_to_pass_closure(), '15')
          assert(this_function_needs_to_take_closure(), '16')
        if current_function().id?.name is 'passesZee'
          assert(scope_below_using(escope_scope(), 'z'))
          assert(!scope_below_using(escope_scope(), 'y'))

      if node.type in ['Identifier'] &&
          current_scope() &&
          is_variable_reference(node, parent) &&
          (this_function_needs_to_take_closure() || (this_function_needs_to_pass_closure() && scope_below_using(escope_scope(), node.name)))
        return ident_to_member_expr(node)

      if /(Switch|Block)Statement/.test(node.type) &&
          this_function_needs_to_pass_closure()
        node.closure = null
        bod = []
        if parent.type in ['FunctionDeclaration', 'FunctionExpression']
          if opt.params != false
            for param in parent.params
              if scope_below_using(escope_scope(), param.name)
                if param.name isnt '_closure'
                  bod.push assignment(
                    util.member(scope_with(param.name).name, param.name),
                    param)
          if opt.fname != false
            for funct in functions_declared(node)
              if scope_below_using(escope_scope(), funct)
                bod.push assignment(
                  util.member(current_scope().name, funct),
                  funct)

        assign_or_declare = (id, init = 'undefined') ->
          if id.type is 'MemberExpression'
            return assignment(id, init)
          else
            assert.equal id.type, 'Identifier'
            return util.declaration(id.name, init)

        extract_var_decls = (_node) ->
          if _node.type is 'VariableDeclaration'
            declosurified = []
            for decl in _node.declarations
              declosurified.push assign_or_declare(decl.id, decl.init)
            return declosurified
          else if _node.type is 'ForInStatement'
            forInVariableName = for_in_name()
            for decl in _node.left.declarations
              _node.body.body.unshift assignment(
                decl.id,
                forInVariableName
              )
              decl.id = util.identifierIfString(forInVariableName)
            return _node
          else if _node.type is 'ForStatement' && _node.init?.type is 'VariableDeclaration'
            decls = _node.init.declarations.map (decl) ->
              assign_or_declare(decl.id, decl.init || util.identifierIfString("undefined"))
            _node.init = null
            return decls.concat(_node)
          return _node

        if node.type is 'BlockStatement'
          bod = bod.concat node.body.map(extract_var_decls).reduce(
            (accum, item) -> accum.concat(item),
            []
          )
          return util.block bod
        else if node.type is 'SwitchStatement'
          for _case in node.cases
            for _node in _case.consequent
              _case.consequent = extract_var_decls(_node)
          return node
        else
          assert false

      return node

  for { func, closureName, scopesAbove } in to_unshift
    if opt.recursiveClosures isnt false &&
        scopesAbove.length isnt 0 &&
        func.params[0]?.name is '_closure'
      [upperClosure, otherClosures...] = scopesAbove
      otherClosures.reverse()  # just so the the assignments are in a prettier order

      for closure in otherClosures
        if closure.name
          func.body.body.unshift(
            assignment(
              util.member(closureName, closure.name),
              util.member('_closure', closure.name)))
      if upperClosure.name
        func.body.body.unshift(
          assignment(
            util.member(closureName, upperClosure.name),
            '_closure'))

    func.body.body.unshift(
      util.declaration(closureName, util.object())
    )

assignment = (args...) -> util.expressionStatement(util.assignment(args...))

is_variable_reference = (node, parent) ->
  assert node.type is 'Identifier'
  if /Function/.test parent.type
    # I'm the argument or name of a function
    return false
  if parent.type is 'MemberExpression'
    # Not all identifiers in MemberExpression s are variables, only when:
    return (
      parent.object is node or  # - identifier is the leftmost in the membex
      (parent.computed and parent.property is node)  # - identifier is in square brackets ( foo[x] )
    )
  # Everything else is a variable reference. Probably.
  return true

is_above = (above, scope) ->
  assert(scope, 'scope is ' + scope)
  assert(above, 'above is ' + above)
  assert(scope.upper != undefined, 'scope is not a scope, its .upper is ' + scope.upper)
  assert(above.upper != undefined, 'above is not a scope, its .upper is ' + above.upper)
  while scope
    scope = scope.upper
    if scope is above
      return true
  return false
