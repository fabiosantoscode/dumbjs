'use strict'

const util = module.exports

Object.assign(util, {
  isFunction: node => node && /^Function/.test(node.type),
  isBlockish: node => node && /^(Switch|Block)Statement/.test(node.type),
  containsBlock: node => util.isFunction(node) || util.isBlockish(node),
})

