assert = require 'assert'
estraverse = require 'estraverse'
util = require './util'

module.exports = (programNode) ->
  _usesOwnNameCache = new Map
  usesOwnName = (functionNode) ->
    if _usesOwnNameCache.has(functionNode)
      return _usesOwnNameCache.get(functionNode)
    functionName = functionNode.id.name
    ret = false
    estraverse.traverse(functionNode, {
      enter: (node, parent) ->
        if node == functionNode || node == functionNode.id
          return
        if node.type == 'Identifier' && node.name == functionName
          ret = true
          return this.break()
    })
    _usesOwnNameCache.set(functionNode, ret)
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

      visited.add(node)

      if /Declaration/.test(node.type)
        return util.declaration(
          node.id.name,
          generate_ownfunction_iife(node)
        )

      return generate_ownfunction_iife(node)
  })

generate_ownfunction_iife = (func) ->
  func.type = 'FunctionDeclaration'
  util.iife([
    func,
    util.return(util.identifier(func.id.name))
  ])

