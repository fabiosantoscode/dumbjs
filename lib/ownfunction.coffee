assert = require 'assert'
estraverse = require 'estraverse'

module.exports = (programNode, opt = {}) ->
  to_add = []  # Array of { var_decl, body, index }
  to_rename = []  # Array of { node, name }
  to_remove = []  # Array of nodes to remove

  _counter = 0
  generate_name = () -> '_ownfunction_' + (_counter++)

  body_stack = [programNode.body]
  currentBody = () -> body_stack[body_stack.length - 1]
  upperBody = () -> body_stack[body_stack.length - 2]

  currentIdx = 0

  usesOwnName = (functionNode) ->
    functionName = functionNode.id?.name
    if not functionName
      return false
    usages = []
    estraverse.traverse(functionNode, {
      enter: (node) ->
        if node is functionNode or 
            node is functionNode.id
          return
        if /Function/.test(node.type)
          return @skip()
        if node.type is 'Identifier' and node.name is functionName
          usages.push(node)
          return @break
    })
    return usages

  estraverse.replace(programNode, {
    enter: (node, parent) ->
      parentBody = parent && parent.body
      if parentBody && parentBody.body
        parentBody = parentBody.body
      if parentBody is currentBody()
        _idx = parentBody.indexOf(node)
        if _idx != -1
          currentIdx = _idx

      if node.type not in ['FunctionExpression', 'FunctionDeclaration']
        return

      body_stack.push(node.body.body)

      ownNameUsages = usesOwnName(node)
      if not ownNameUsages.length
        return

      newName = generate_name()

      if node.type is 'FunctionExpression'
        to_remove.push(node)
        varDeclInit = JSON.parse(JSON.stringify(node))
        ownNameUsages = usesOwnName(varDeclInit)
        replaceWith = { type: 'Identifier', name: newName }

      to_add.push({
        var_decl: {
          type: 'VariableDeclaration',
          kind: 'var',
          declarations: [{
            type: 'VariableDeclarator',
            id: { type: 'Identifier', name: newName },
            init: varDeclInit or { type: 'Identifier', name: node.id.name }
          }]
        },
        body: upperBody(),
        index: currentIdx
      })

      for ident in ownNameUsages
        to_rename.push({ node: ident, name: newName })

      return replaceWith or node
    leave: (node) ->
      if node.type in ['FunctionExpression', 'FunctionDeclaration']
        body_stack.pop()
      return node
  })

  # Careful: this must run before to_rename because mutable stuff
  estraverse.replace(programNode, {
    leave: (node) ->
      if to_remove.indexOf(node) isnt -1
        return @remove()
  })

  for { var_decl, body, index } in to_add.reverse()
    body.splice(index, 0, var_decl)

  for { node, name } in to_rename
    node.name = name


