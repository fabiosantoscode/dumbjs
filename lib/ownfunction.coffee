assert = require 'assert'
estraverse = require 'estraverse'
util = require './util'

module.exports = (programNode) ->
  usesOwnName = (functionNode) ->
    functionName = functionNode.id.name
    ret = false
    estraverse.traverse(functionNode, {
      enter: (node) ->
        if node == functionNode || node == functionNode.id
          return
        if /Function/.test(node.type)
          return this.skip()
        if node.type == 'Identifier' && node.name == functionName
          ret = true
          return this.break()
    })
    return ret

  visited = new Set

  return estraverse.replace(programNode, {
    enter: (node, parent) ->
      if !/^Function/.test(node.type) ||
          visited.has(node) ||
          !node.id
        return

      if !usesOwnName(node)
        return

      newName = node.id.name

      node.id = null

      visited.add(node)

      if /Declaration/.test(node.type)
        node.type = 'FunctionExpression'
        wasDeclaration = true
        return util.declaration(
          newName,
          generate_ownfunction_iife(node, newName)
        )

      return generate_ownfunction_iife(node, newName)
  })

generate_ownfunction_iife = (ast, name) ->
  util.iife([
    util.declaration(name, ast),
    util.return(util.identifier(name))
  ])

