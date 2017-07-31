'use strict'

const estraverse = require('estraverse')

const util = require('./util')

module.exports = function deregexenise(ast) {
  estraverse.replace(ast, {
    enter: node => {
      if (node.regex) {
        const { pattern, flags } = node.regex
        return util.new('RegExp', [
          util.literal(pattern),
          ...(flags ? [util.literal(flags)] : [])
        ])
      }
    }
  })
  return ast
}

