
estraverse = require 'estraverse'
assert = require 'assert'

module.exports = (ast) ->
  estraverse.replace ast,
    leave: (node) ->
      if node.type is 'ObjectExpression' and node.properties.length
        { properties } = node
        assignments = properties.map(({ key, value, computed }) ->
          return {
            type: 'ExpressionStatement',
            expression: {
              type: 'AssignmentExpression',
              operator: '=',
              left: {
                type: 'MemberExpression',
                computed: key.type isnt 'Identifier',
                object: {
                  type: 'Identifier',
                  name: 'ret',
                },
                property: key,
              },
              right: value,
            },
          }
        )

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

