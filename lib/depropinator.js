'use strict'

var estraverse = require('estraverse')
var assert = require('assert')

module.exports = function depropinator (ast) {
  estraverse.replace(ast, {
    leave: function (node) {
      if (node.type !== 'ObjectExpression' || !node.properties.length) {
        return
      }

      var properties = node.properties
      var assignments = properties.map(function (prop) {
        return {
          type: 'ExpressionStatement',
          expression: {
            type: 'AssignmentExpression',
            operator: '=',
            left: {
              type: 'MemberExpression',
              computed: prop.key.type !== 'Identifier',
              object: {
                type: 'Identifier',
                name: 'ret',
              },
              property: prop.key,
            },
            right: prop.value,
          },
        }
      })

      return {
        type: 'CallExpression',
        arguments: [],
        callee: {
          type: 'FunctionExpression',
          params: [],
          id: null,
          body: {
            type: 'BlockStatement',
            body: ([
              {
                type: 'VariableDeclaration',
                kind: 'var',
                declarations: [
                  {
                    type: 'VariableDeclarator',
                    id: {
                      type: 'Identifier',
                      name: 'ret'
                    },
                    init: {
                      type: 'ObjectExpression',
                      properties: [],
                    }
                  }
                ]
              }
            ]).concat(assignments).concat([
              {
                type: 'ReturnStatement',
                argument: {
                  type: 'Identifier',
                  name: 'ret'
                }
              }
            ]),
          },
        },
      }
    }
  })
}
