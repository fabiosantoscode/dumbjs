'use strict'

const assert = require('assert')
const estraverse = require('estraverse')

const util = require('./util')

module.exports = (ast) => {
  const generateForInName = util.nameSluginator('_for_in_');
  ast = estraverse.replace(ast, {
    enter: node => {
      if (node.type === 'ExpressionStatement') {
        if (node.expression.type === 'Literal') {
          return estraverse.VisitorOption.Remove
        }
        return node
      } else if (node.type === 'Literal') {
        return node
      } else if (util.isBlockish(node)) {
        return util.replaceStatements(node, node => extractDecls(node, generateForInName))
      } else if (supportedNodeTypes.has(node.type)) {
        return node
      } else {
        throw new Error('Unknown node type ' + node.type + ' in ' + node)
      }
    }
  })

  return ast
}

const extractDecls = (node, generateForInName) => {
  if (node.type === 'VariableDeclaration' && node.declarations.length !== 1) {
    return multipleDeclarations(node.declarations, node.kind)
  }
  if (node.type === 'ForInStatement') {
    return extractDeclarationFromForIn(node, generateForInName)
  }
  if (node.type === 'ForStatement' && (node.init || {}).type === 'VariableDeclaration') {
    const init = node.init
    node.init = null
    return multipleDeclarations(init.declarations, init.kind).concat([node])
  }
  return node
}

const multipleDeclarations = (decls, kind) =>
  decls.map(decl => ({
    type: 'VariableDeclaration',
    declarations: [decl],
    kind: kind
  }))

const extractDeclarationFromForIn = (node, generateForInName) => {
  const wasDeclaration = node.left.type === 'VariableDeclaration'
  const assignOrDecl = wasDeclaration ? util.declaration : util.assignment;
  const realName = wasDeclaration
    ? node.left.declarations[0].id.name
    : node.left.name
  const shimName = generateForInName()
  node.left = util.declaration(shimName)
  node.body.body.unshift(assignOrDecl(realName, shimName))
  return node
}

const supportedNodeTypes = [
  'Program',
  'Identifier',
  'CallExpression',
  'BlockStatement',
  'FunctionExpression',
  'FunctionDeclaration',
  'VariableDeclaration',
  'VariableDeclarator',
  'IfStatement',
  'UnaryExpression',
  'MemberExpression',
  'LogicalExpression',
  'BinaryExpression',
  'ContinueStatement',
  'TryStatement',
  'CatchClause',
  'ReturnStatement',
  'NewExpression',
  'ThrowStatement',
  'SequenceExpression',
  'AssignmentExpression',
  'ObjectExpression',
  'Property',
  'ConditionalExpression',
  'ForStatement',
  'ForInStatement',
  'UpdateExpression',
  'ArrayExpression',
  'ThisExpression',
  'SwitchStatement',
  'SwitchCase',
  'BreakStatement',
  'WhileStatement',
  'DoWhileStatement',
  'EmptyStatement'
].reduce((accum, item) => accum.add(item), new Set())

