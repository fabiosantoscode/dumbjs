'use strict'

const estraverse = require('estraverse')
const assert = require('assert')
const util = require('./util')

module.exports = function depropinator (ast) {
  estraverse.replace(ast, {
    leave: node => {
      if (node.type !== 'ObjectExpression' || !node.properties.length) {
        return
      }

      return makeIIFEThatAssignsEachProperty(node)
    }
  })
}

function makeIIFEThatAssignsEachProperty(node) {
  const assignments = node.properties.map(prop =>
    util.expressionStatement(
      util.assignment(
        util.member(
          'ret',
          prop.key,
          /*computed=*/prop.key.type !== 'Identifier'
        ),
        prop.value
      )
    )
  )

  return util.iife([
    util.declaration('ret', util.object()),
    ...assignments,
    util.return(util.identifier('ret')),
  ])
}
