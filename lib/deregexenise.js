'use strict'

const estraverse = require('estraverse')

const ident = (name) => ({ type: 'Identifier', name })
const literal = (value) => ({ type: 'Literal', value })

module.exports = function deregexenise(ast) {
  estraverse.replace(ast, {
    enter: node => {
      if (node.regex) {
        const { pattern, flags } = node.regex
        return {
          type: 'NewExpression',
          callee: ident('RegExp'),
          arguments: [
            literal(pattern),
            ...(flags ? [literal(flags)] : [])
          ]
        }
      }
    }
  })
  return ast
}

