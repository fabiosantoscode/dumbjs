assert = require('assert')
escope = require('escope')
estraverse = require('estraverse')
util = require('./util')
nameSluginator = util.nameSluginator

# Shoves functions up, making sure there are no nested functions in the codez

specificAssignee = (assignment) ->
  if assignment.type == 'Identifier'
    assignment.name
  else if assignment.left.type == 'Identifier'
    assignment.left.name
  else if assignment.left.type == 'MemberExpression'
    specificAssignee(assignment.left.property)
  else
    ''

findNiceFunctionName = (func, parent) ->
  if func.id
    func.id.name
  else if parent?.type is 'AssignmentExpression'
    specificAssignee parent
  else
    ''

module.exports = (programNode) ->
  assert(typeof programNode.body.length == 'number')
  insertFuncs = []
  insertVars = []
  changeNames = []
  currentIdx = 0
  scopeMan = escope.analyze programNode
  scopeStack = [ scopeMan.acquire(programNode) ]
  currentScope = () ->
    return scopeStack[scopeStack.length - 1]
  generateName = nameSluginator('_flatten_')

  estraverse.traverse(programNode, {
    enter: (node) ->
      if util.isFunction(node)
        scope = scopeMan.acquire(node)
        if scope.type == 'function-expression-name'
          scope = scope.childScopes[0]
        scopeStack.push(scope)
    leave: (node, parent) ->
      if util.isFunction(node)
        scopeStack.pop()

      if parent && parent.type == 'Program'
        currentIdx = parent.body.indexOf(node)
        assert currentIdx > -1

      # Shove them upwards!
      if (parent && parent.type) != 'Program'
        if node.type == 'FunctionDeclaration'
          newName = generateName(node.id && node.id.name)
          changeNames.push({ id: node.id, name: newName })
          for ref in currentScope().references
            if ref.identifier.name == node.id.name
              changeNames.push({ id: ref.identifier, name: newName })
          insertFuncs.push({ insert: node, into: currentIdx })
        if node.type == 'FunctionExpression'
          variable = generateName(findNiceFunctionName(node, parent))
          insertVars.push({ insert: node, into: currentIdx, variable: variable })

        if util.isFunction(node) && node.id
          functionName = node.id
          scopeInsideFunction = scopeMan.acquire(node)
          for ref in scopeInsideFunction.references
            if ref.resolved && ref.resolved.defs[0] &&
                ref.resolved.defs[0].type == 'FunctionName' and
                ref.resolved.defs[0].node.id == functionName
              changeNames.push({ id: ref.identifier, name: newName })
  })

  estraverse.replace(programNode, {
    leave: (node, parent) ->
      for { insert } in insertFuncs
        if node == insert
          return this.remove()
      for { insert, variable } in insertVars
        if node == insert
          return util.identifier(variable)
      return node
  })

  changeNames.forEach((toChange) ->
    toChange.id.name = toChange.name
  )
  insertFuncs.forEach((toInsert) -> programNode.body.splice(toInsert.into, 0, toInsert.insert))
  insertVars.forEach((toInsert) ->
    programNode.body.splice(toInsert.into, 0, util.declaration(toInsert.variable, toInsert.insert))
  )

