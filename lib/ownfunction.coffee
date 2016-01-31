assert = require 'assert'
estraverse = require 'estraverse'

module.exports = (programNode, opt) ->
  opt = opt || {}
  to_add = []  # Array of { var_decl, body, index }
  to_rename = []  # Array of { node, name }
  to_remove = []  # Array of nodes to remove

  _counter = 0
  generate_name = () ->
    return '_ownfunction_' + (_counter++)

  body_stack = [programNode.body]
  currentBody = () ->
    return body_stack[body_stack.length - 1]
  upperBody = () ->
    return body_stack[body_stack.length - 2]

  currentIdx = 0

  usesOwnName = (functionNode) ->
    if !functionNode.id
      return false
    functionName = functionNode.id.name
    usages = []
    estraverse.traverse(functionNode, {
      enter: (node) ->
        if node == functionNode || node == functionNode.id
          return
        if /Function/.test(node.type)
          return this.skip()
        if node.type == 'Identifier' && node.name == functionName
          usages.push(node)
          return this.break
    })
    return usages

  estraverse.replace(programNode, {
    enter: (node, parent) ->
      parentBody = parent && parent.body
      if parentBody && parentBody.body
        parentBody = parentBody.body
      if parentBody == currentBody()
        _idx = parentBody.indexOf(node)
        if _idx != -1
          currentIdx = _idx

      if !/^Function/.test(node.type)
        return

      body_stack.push(node.body.body)

      ownNameUsages = usesOwnName(node)
      if !ownNameUsages.length
        return

      newName = generate_name()

      if node.type == 'FunctionExpression'
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
      if to_remove.indexOf(node) != -1
        return this.remove()
  })

  for { var_decl, body, index } in to_add.reverse()
    body.splice(index, 0, var_decl)

  for { node, name } in to_rename
    node.name = name


