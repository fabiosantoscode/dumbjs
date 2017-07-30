assert = require('assert')
path = require('path')
fs = require('fs')

esprima = require('esprima')

estraverse = require('estraverse')
resolveSync = require('resolve').sync

util = require('./util')

coreModules = fs.readdirSync(__dirname + '/../node/lib')
  .map((mod) => mod.replace(/\.js$/, ''))

module.exports = (ast, { readFileSync = fs.readFileSync, foundModules = {}, filename = '', isMain = true, sluginator = null, _doWrap = true, resolve = resolveSync, slug, _recurse } = {}) ->
  if not sluginator
    sluginator = util.nameSluginator()

  dirname = path.dirname(filename)
  justTheFilename = path.basename(filename)

  otherModules = []
  findModules ast, resolve, dirname, (resolvedFilename) ->
    _slug = foundModules[resolvedFilename]
    if not _recurse
      _recurse = module.exports
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
          return {
            type: 'CallExpression',
            callee: { type: 'Identifier', name: newName },
            arguments: []
          }
  })

wrapModuleContents = ({ body, filename = '', dirname = '' }) ->
  return [
    {
      "type": "VariableDeclaration",
      "kind": "var",
      "declarations": [{
        "type": "VariableDeclarator",
        "id": { "type": "Identifier", "name": "module" },
        "init": {
          "type": "ObjectExpression",
          "properties": []
        }
      }],
    }, {
      "type": "VariableDeclaration",
      "kind": "var",
      "declarations": [{
        "type": "VariableDeclarator",
        "id": { "type": "Identifier", "name": "__filename" },
        "init": { "type": "Literal", "value": filename, }
      }],
    }, {
      "type": "VariableDeclaration",
      "kind": "var",
      "declarations": [{
        "type": "VariableDeclarator",
        "id": { "type": "Identifier", "name": "__dirname" },
        "init": { "type": "Literal", "value": dirname, }
      }],
    },
  ].concat(body).concat([
    {
      "type": "ReturnStatement",
      "argument": {
        "type": "MemberExpression",
        "computed": false,
        "object": { "type": "Identifier", "name": "module" },
        "property": { "type": "Identifier", "name": "exports" }
      }
    }
  ])

generateRequirerFunction = ({ slug, dirname, filename, body }) -> [
  {
    "type": "VariableDeclaration",
    "kind": "var"
    "declarations": [{
      "type": "VariableDeclarator",
      "id": { "type": "Identifier", "name": "_was_module_initialised#{slug}" },
      "init": { "type": "Literal", "value": false }
    }],
  }, {
    "type": "VariableDeclaration",
    "kind": "var"
    "declarations": [{
      "type": "VariableDeclarator",
      "id": { "type": "Identifier", "name": "_module#{slug}" },
      "init": null
    }],
  }, {
    "type": "FunctionDeclaration",
    "id": { "type": "Identifier", "name": "_require#{slug}" },
    "params": [],
    "defaults": [],
    "body": {
      "type": "BlockStatement",
      "body": [{
        "type": "FunctionDeclaration",
        "id": { "type": "Identifier", "name": "_initmodule#{slug}" },
        "params": [],
        "defaults": [],
        "body": {
          "type": "BlockStatement",
          "body": wrapModuleContents({ body, filename, dirname }),
        },
        "generator": false,
        "expression": false
      }, {
        "type": "IfStatement",
        "test": { "type": "Identifier", "name": "_was_module_initialised#{slug}" },
        "consequent": {
          "type": "BlockStatement",
          "body": [{
            "type": "ReturnStatement",
            "argument": { "type": "Identifier", "name": "_module#{slug}" }
          }]
        },
        "alternate": null
      }, {
        "type": "ExpressionStatement",
        "expression": {
          "type": "AssignmentExpression",
          "operator": "=",
          "left": { "type": "Identifier", "name": "_module#{slug}" },
          "right": {
            "type": "CallExpression",
            "callee": { "type": "Identifier", "name": "_initmodule#{slug}" },
            "arguments": []
          },
        }
      }, {
        "type": "ReturnStatement",
        "argument": { "type": "Identifier", "name": "_module#{slug}" }
      }]
    },
    "generator": false,
    "expression": false
  }
]

