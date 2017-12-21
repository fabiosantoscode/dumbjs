'use strict'

const assert = require('assert')
const path = require('path')
const fs = require('fs')

const esprima = require('esprima')

const estraverse = require('estraverse')
const resolveSync = require('resolve').sync

const util = require('./util')

const coreModules = fs.readdirSync(__dirname + '/../node/lib')
  .map((mod) => mod.replace(/\.js$/, ''))

module.exports = (ast, {
  readFileSync = fs.readFileSync,
  foundModules = {},
  filename = '',
  isMain = true,
  sluginator = null,
  _doWrap = true,
  resolve = resolveSync,
  slug,
  _recurse = module.exports,
  transformRequiredModule
} = {}) => {
  if (!sluginator) {
    sluginator = util.nameSluginator()
  }

  const dirname = path.dirname(filename)
  const justTheFilename = path.basename(filename)

  let otherModules = []
  findModules(ast, resolve, dirname, (resolvedFilename) => {
    let slug = foundModules[resolvedFilename]
    if (!slug) {
      slug = sluginator(path.basename(resolvedFilename).replace(/\.js$/, ''))
      let ast = esprima.parse(readFileSync(resolvedFilename) + '')
      if (transformRequiredModule) {
        ast = transformRequiredModule(ast)
      }
      foundModules[resolvedFilename] = slug
      const thisModule = _recurse(ast, {
        readFileSync,
        foundModules,
        filename: resolvedFilename,
        isMain: false,
        sluginator,
        _doWrap,
        _recurse,
        resolve,
        slug: slug,
        transformRequiredModule,
      })
      otherModules = otherModules.concat([thisModule.body])
    }
    return '_require' + slug
  })

  if (
    _doWrap !== false &&
    isMain === false
  ) {
    if (!slug) slug = sluginator(justTheFilename.replace(/\.js$/i, ''))
    protectExportsAssignments(ast.body)
    ast.body = generateRequirerFunction({ slug, dirname, filename, body: ast.body })
    assert(typeof ast.body.length === 'number')
  }

  ast.body = otherModules
    .reduce(
      (accum, bod) => accum.concat(bod),
      [])
    .concat(ast.body)

  return ast
}

const findModules = (ast, resolve, dirname, getModuleSlug) =>
  estraverse.replace(ast, {
    leave: (node) => {
      // TODO check for things called "require" in the same scope
      if (node.type === 'CallExpression' &&
          node.callee.name === 'require' &&
          node.arguments.length === 1 &&
          node.arguments[0].type === 'Literal') {
        const moduleName = node.arguments[0].value
        let resolved
        if (coreModules.indexOf(moduleName) != -1) {
          resolved = __dirname + `/../node/lib/${moduleName}.js`
        } else {
          resolved = resolve(moduleName, { basedir: dirname })
        }
        const newName = getModuleSlug(resolved, node.arguments[0].value)
        if (newName) {
          return util.call(newName)
        }
      }
    }
  })

const protectExportsAssignments = body => {
  body.forEach(statement => {
    estraverse.traverse(statement, {
      enter: node => {
        if (node.type === 'AssignmentExpression' &&
            node.left.type === 'MemberExpression' &&
            node.left.object.name === 'module' &&
            node.left.property.name === 'exports') {
          throw new Error('Assigning to module.exports is forbidden!')
        }
      }
    })
  })
}

const wrapModuleContents = ({ body, filename = '', dirname = '', slug }) => [
  util.declaration('module', util.object({
    exports: '_module' + slug
  })),
  util.declaration('exports', '_module' + slug),
  util.declaration('__filename', util.literal(filename)),
  util.declaration('__dirname', util.literal(dirname)),
  ...body,
  util.return('_module' + slug)
]

const generateRequirerFunction = ({ slug, dirname, filename, body }) => [
  util.declaration('_was_module_initialised' + slug, util.literal(false)),
  util.declaration('_module' + slug, util.object()),
  util.functionDeclaration({
    id: '_initmodule' + slug,
    body: wrapModuleContents({ slug, body, filename, dirname })
  }),
  util.functionDeclaration({
    id: '_require' + slug,
    body: [
      util.if(
        util.identifier('_was_module_initialised' + slug),
        util.return('_module' + slug)
      ),
      util.expressionStatement(
        util.assignment(
          '_module' + slug,
          util.call('_initmodule' + slug)
        )
      ),
      util.return('_module' + slug)
    ]
  })
]

