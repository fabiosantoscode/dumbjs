'use strict'

exports.nameSluginator = function (prefix) {
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

exports.iife = (body) => exports.call({
  type: 'FunctionExpression',
  params: [],
  body: { type: 'BlockStatement', body }
})
exports.call = (callee, ...args) => ({
  type: 'CallExpression',
  arguments: args,
  callee
})
exports.declaration = (name, init) => ({
  type: 'VariableDeclaration',
  kind: 'var',
  declarations: [
    { type: 'VariableDeclarator', id: exports.identifier(name), init }
  ]
})
exports.return = argument => ({ type: 'ReturnStatement', argument })
exports.identifierIfString = string => {
  if (typeof string === 'string') {
    return exports.identifier(string)
  }
  return string
}
exports.identifier = name => ({ type: 'Identifier', name })

