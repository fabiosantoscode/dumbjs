assert = require('assert')
path = require('path')
fs = require('fs')

esprima = require('esprima')

estraverse = require('estraverse')
resolveSync = require('resolve').sync

util = require('./util')

coreModules = fs.readdirSync(__dirname + '/../node/lib')
  .map((mod) => mod.replace(/\.js$/, ''))

module.exports = (ast, { readFileSync = fs.readFileSync, foundModules = {}, filename = '', isMain = true, sluginator = null, _doWrap = true, resolve = resolveSync, slug, _recurse = module.exports } = {}) ->
  if not sluginator
    sluginator = util.nameSluginator()

  dirname = path.dirname(filename)
  justTheFilename = path.basename(filename)

  otherModules = []
  findModules ast, resolve, dirname, (resolvedFilename) ->
    _slug = foundModules[resolvedFilename]
    if not _slug
      _slug = sluginator(path.basename(resolvedFilename).replace(/\.js$/, ''))
      _ast = esprima.parse(readFileSync(resolvedFilename) + '')
      foundModules[resolvedFilename] = _slug
      thisModule = _recurse(_ast, {
        readFileSync,
        foundModules,
        filename: resolvedFilename,
        isMain: false,
        sluginator,
        _doWrap,
        resolve,
        slug: _slug,
      })
      otherModules = otherModules.concat([thisModule.body])
    return '_require' + _slug

  if _doWrap isnt false and
      isMain is false
    if not slug
      slug = sluginator(justTheFilename.replace(/\.js$/i, ''))
    ast.body = generateRequirerFunction({ slug, dirname, filename, body: ast.body })
    assert typeof ast.body.length is 'number'

  ast.body = otherModules
    .reduce(
      (accum, bod) -> accum.concat(bod),
      [])
    .concat(ast.body)

  return ast

findModules = (ast, resolve, dirname, getModuleSlug) ->
  estraverse.replace(ast, {
    leave: (node) ->
      # TODO check for things called "require" in the same scope
      if node.type is 'CallExpression' and
          node.callee.name is 'require' and
          node.arguments.length is 1 and
          node.arguments[0].type is 'Literal'
        moduleName = node.arguments[0].value
        if coreModules.indexOf(moduleName) != -1
          resolved = __dirname + "/../node/lib/#{moduleName}.js"
        else
          resolved = resolve(moduleName, { basedir: dirname })
        newName = getModuleSlug(resolved, node.arguments[0].value)
        if newName
          return util.call(newName)
  })

wrapModuleContents = ({ body, filename = '', dirname = '' }) -> [
  util.declaration('module', util.object()),
  util.declaration('__filename', util.literal(filename)),
  util.declaration('__dirname', util.literal(dirname)),
  body...,
  util.return(util.member('module', 'exports'))
]

generateRequirerFunction = ({ slug, dirname, filename, body }) -> [
  util.declaration('_was_module_initialised' + slug, util.literal(false)),
  util.declaration('_module' + slug)
  util.functionDeclaration({
    id: '_initmodule' + slug,
    body: wrapModuleContents({ body, filename, dirname })
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

