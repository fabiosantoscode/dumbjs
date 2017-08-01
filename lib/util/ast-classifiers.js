'use strict'

const util = module.exports

Object.assign(util, {
  isFunction: node => node && /^Function/.test(node.type),
  isBlockish: node => node &&
    (/^(Switch|Block)Statement/.test(node.type) || node.type === 'Program'),
  containsBlock: node => util.isFunction(node) || util.isBlockish(node),
  isVariableReference: (node, parent) => {
    if (node.type !== 'Identifier') {
      return false
    }
    if (util.isFunction(parent)) {
      // This is an argument or name of a function
      return false
    }
    if (parent.type === 'MemberExpression') {
      return Boolean(
        // - identifier is the leftmost in the membex
        parent.object === node ||
        // - identifier is in square brackets ( foo[x] )
        (parent.computed && parent.property === node)
      )
    }
    // Everything else is probably a ref
    return true
  }
})

