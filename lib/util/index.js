'use strict'

const estraverse = require('estraverse')
const escopeModule = require('escope')

const util = module.exports

const builders = require('./ast-builders')
const classifiers = require('./ast-classifiers')

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

