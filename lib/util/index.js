'use strict'

const assert = require('assert')

const estraverse = require('estraverse')
const escopeModule = require('escope')
const flatten = require('lodash/flatten')

const builders = require('./ast-builders')
const classifiers = require('./ast-classifiers')

const util = module.exports

util.nameSluginator = function (prefix) {
  prefix = prefix || '_'
  function sluginator (name) {
    return prefix + name.replace(/./g, function (char) {
      if (!/[a-zA-Z0-9_]/.test(char)) return ''
      return char
    })
  }
  var _nameCounter = 0
  var _namesUsed = []
  function generateName (name) {
    if (name) {
      var name = sluginator(name)
      if (_namesUsed.indexOf(name) === -1) {
        _namesUsed.push(name)
        return name
      }
    }
    return '' + prefix + '' + (_nameCounter++)
  }

  return generateName
}

util.escopeOfFunction = (scopeMan, node) => {
  const ret = scopeMan.acquire(node)
  if (ret.type === 'function-expression-name') {
    return ret.childScopes[0]
  }
  return ret
}

util.replaceStatements = (blockish, mapFn, { prepend } = {}) => {
  assert(util.isBlockish(blockish), 'replaceStatements called with non-blockish')
  if (blockish.type == 'BlockStatement') {
    return Object.assign(blockish, {
      body: flatten([prepend].concat(blockish.body.map(mapFn))).filter(Boolean),
    })
  }
  if (blockish.type == 'Program') {
    return Object.assign(blockish, {
      body: flatten([prepend].concat(blockish.body.map(mapFn))).filter(Boolean),
    })
  }
  if (blockish.type == 'SwitchStatement') {
    const ret = Object.assign(blockish, {
      cases: blockish.cases.map(kase =>
        Object.assign(kase, {
          consequent: flatten(kase.consequent.map(mapFn)).filter(Boolean)
        })
      )
    })

    if (prepend) {
      return util.block(
        flatten([prepend].concat(ret)).filter(Boolean)
      )
    }

    return ret
  }
  assert(false)
}

Object.keys(builders).forEach(k => {
  Object.defineProperty(util, k, {
    get: () => builders[k]
  })
})

Object.keys(classifiers).forEach(k => {
  Object.defineProperty(util, k, {
    get: () => classifiers[k]
  })
})

