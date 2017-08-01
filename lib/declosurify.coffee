assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'
flatten = require 'lodash/flatten'
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

  closure_name = util.nameSluginator('_closure_')

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

  functions_declared = (functionNode, { nodes } = {}) ->
    if opt.funcs is false
      return []
    funcs = []
    # Look for function declarations with the given name.
    # For some reason tern doesn't give me this?
    estraverse.traverse(functionNode, {
      enter: (node) ->
        if node is functionNode
          return

        node_to_push = null
        name_to_push = null

        if node.type is 'FunctionDeclaration' && node.id
          node_to_push = node
          name_to_push = node.id.name
        if node.type is 'VariableDeclaration'
          decl = node.declarations[0]
          if util.isFunction(decl.init)
            node_to_push = decl.init
            if decl.id.type == 'MemberExpression'
              # TODO why are there declarators with member expressions on the left?
              name_to_push = decl.id.property.name
            else
              name_to_push = decl.id.name
        if node_to_push
          if nodes
            funcs.push [ node_to_push, name_to_push ]
          else
            funcs.push name_to_push
        if util.isFunction(node)
          return @skip()
    })
    return funcs

  current_function = () -> scope_stack[scope_stack.length - 1].originNode

  getTernScopePath = (_from) ->
    _from = _from || 2
    tern_scope = scope_stack[scope_stack.length - _from]
    # TODO below line works works but depends on mutable state.
    uses_upper_closure = tern_scope && tern_scope.originNode.params[0]?.name is '_closure'
    if uses_upper_closure
      return [tern_scope].concat(getTernScopePath(_from + 1))
    if tern_scope
      return [tern_scope]
    return []

  to_unshift = []  # We keep notes of { func, closureName, ternScopePath } so we add var _closure_X = {} later.

  all_functions_below = (func) ->
    funcs = []
    estraverse.traverse(func, {
      enter: (node) ->
        if node is func
          return
        if util.isFunction(node)
          funcs.push node
    })
    return funcs

  this_function_passes_closure = () ->
    if opt.always_create_closures
      return true
    for variable in escope_scope().variables
      if variable.stack is false
        return true
    if util.isFunction(escope_scope().block)
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

  this_function_takes_closure = () ->
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

  ident_refers_to_a_function = (ident) ->
    ref = escope_scope().resolve(ident)
    if ref?.resolved
      def = ref.resolved.defs.find((def) -> def.type == 'FunctionName')
      if def
        return true

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

  should_turn_ident_into_member_expression = (ident, parent) ->
    is_ref = current_scope() && util.isVariableReference(ident, parent)
    if !is_ref
      return false
    is_for_in_variable = (
      ident.name.startsWith('_for_in_')
    )
    if is_for_in_variable
      return false
    shared_with_lower_scope = (
      this_function_passes_closure() &&
      scope_below_using(escope_scope(), ident.name)
    )
    is_func_ref = (
      ident_refers_to_a_function(ident) &&
      parent.id isnt ident
    )
    return (
      this_function_takes_closure() || shared_with_lower_scope || is_func_ref
    )

  estraverse.replace programNode,
    enter: (node, parent) ->
      if util.isFunction(node)
        escope_scope_stack.push(scope_of_function(node))
        scope_stack.push node.scope
        assert node.scope

        if this_function_passes_closure()
          node.scope.name = closure_name()
          to_unshift.push({
            func: node,
            closureName: node.scope.name,
            ternScopePath: getTernScopePath(),
          })

        if this_function_takes_closure()
          if parent isnt programNode &&
              opt.recursiveClosures isnt false
            node.params.unshift(util.identifier('_closure'))

      return node
    leave: (node, parent) ->
      if util.isFunction(node)
        escope_scope_stack.pop()
        scope_stack.pop()
        return

      if node.type in ['Identifier'] &&
          should_turn_ident_into_member_expression(node, parent)
        return ident_to_member_expr(node)

      if util.isBlockish(node) && this_function_passes_closure()
        bod = []
        if util.isFunction(parent)
          if opt.params != false
            for param in parent.params
              if scope_below_using(escope_scope(), param.name)
                if param.name isnt '_closure'
                  bod.push assignment(
                    util.member(scope_with(param.name).name, param.name),
                    param)
          if opt.fname != false
            for [ funct, name ] in functions_declared(parent, { nodes: true })
              bod.push assignment(
                util.member(current_scope().name, name),
                name)

        assign_or_declare = (id, init = 'undefined') ->
          if id.type is 'MemberExpression'
            return assignment(id, init)
          else
            assert.equal id.type, 'Identifier'
            return util.declaration(id.name, init)

        extract_var_decls = (_node) ->
          if _node.type is 'VariableDeclaration'
            declosurified = []
            decl = _node.declarations[0]
            if decl.init?.type isnt 'FunctionExpression'
              return assign_or_declare(decl.id, decl.init)
            else if decl.init
              if decl.id.type is 'MemberExpression'
                fName = decl.id.property.name
              else
                fName = decl.id.name

              decl.init.type = 'FunctionDeclaration'
              decl.init.id = util.identifier(fName)

              return decl.init
          return _node

        return util.replaceStatements(node, extract_var_decls, { prepend: bod })

      return node

  for { func, closureName, ternScopePath } in to_unshift
    if opt.recursiveClosures isnt false &&
        ternScopePath.length isnt 0 &&
        func.params[0]?.name is '_closure'
      [upperClosure, otherClosures...] = ternScopePath
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

function_needs_closure = (funct) -> Boolean(funct.params.find((parm) -> parm.name is '_closure'))

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
