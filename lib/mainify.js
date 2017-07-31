'use strict'

const util = require('./util');

module.exports = function (ast, { prepend = [], append = [] } = { }) {
  ast.body = [
    util.functionDeclaration({
      id: 'main',
      body: [...prepend, ...ast.body, ...append]
    })
  ]
  return ast
}
