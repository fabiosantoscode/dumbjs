assert = require 'assert'
escope = require 'escope'
estraverse = require 'estraverse'


# Shoves functions up, making sure there are no nested functions in the codez

module.exports = (programNode) ->
  assert typeof programNode.body.length is 'number'
  insertFuncs = []
  insertVars = []
  changeNames = []
  currentIdx = 0
  counter = 0
  scopeMan = escope.analyze programNode
  scopeStack = [ scopeMan.acquire(programNode) ]
  currentScope = () -> scopeStack[scopeStack.length - 1]

  estraverse.traverse programNode,
    enter: (node) ->
      if /Function/.test node.type
        scope = scopeMan.acquire(node)
        if scope.type is 'function-expression-name'
          scope = scope.childScopes[0]
        scopeStack.push(scope)
    leave: (node, parent) ->
      if /Function/.test node.type
        scopeStack.pop()

      if parent?.type is 'Program'
        currentIdx = parent.body.indexOf node
        assert currentIdx > -1

      # Shove them upwards!
      if parent?.type isnt 'Program'
        if node.type is 'FunctionDeclaration'
          newName = "_flatten_#{counter++}"
          changeNames.push({ id: node.id, name: newName })
          for ref in currentScope().references
            if ref.identifier.name == node.id.name
              changeNames.push({ id: ref.identifier, name: newName })
          insertFuncs.push({ insert: node, into: currentIdx })
        if node.type is 'FunctionExpression'
          variable = "_flatten_#{counter++}"
          insertVars.push({ insert: node, into: currentIdx, variable: variable })

        if /Function/.test(node.type) and node.id
          functionName = node.id
          scopeInsideFunction = scopeMan.acquire(node)
          for ref in scopeInsideFunction.references
            if ref.resolved?.defs[0]?.type is 'FunctionName' and
                ref.resolved?.defs[0]?.node.id is functionName
              changeNames.push({ id: ref.identifier, name: newName })

  estraverse.replace programNode,
    leave: (node, parent) ->
      for { insert } in insertFuncs
        if node is insert
          @remove()
          return undefined
      for { insert, variable } in insertVars
        if node is insert
          return { type:'Identifier', name: variable }
      return node

  changeNames.forEach ({ id, name }) -> id.name = name
  insertFuncs.forEach ({ insert, into }) -> programNode.body.splice(into, 0, insert)
  insertVars.forEach ({ insert, into, variable }) ->
    programNode.body.splice(into, 0, makeDeclaration(variable, insert))

makeDeclaration = (name, value) -> {
    type: "VariableDeclaration",
    kind: "var",
    declarations: [{
      type: "VariableDeclarator",
      id: {
        type: "Identifier",
        name: name,
      },
      init: value,
    }],
  }
