'use strict'

const util = module.exports

Object.assign(util, {
  isFunction: node => node && /^Function/.test(node.type)
})

