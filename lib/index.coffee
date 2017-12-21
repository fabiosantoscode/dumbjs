fs = require 'fs'
assert = require 'assert'
escope = require 'escope'
escodegen = require 'escodegen'
estraverse = require 'estraverse'
child_process = require 'child_process'

astValidator = require '../vendor/js-ast-validator/check-ast'

parse = require './parse'
basicTransforms = require './basic-transforms'
requireObliteratinator = require './require-obliteratinator'
typeConversions = require './type-conversions'
topmost = require './topmost'
declosurify = require './declosurify'
bindify = require './bindify'
mainify = require './mainify'
thatter = require './thatter'
depropinator = require './depropinator'
deregexenise = require './deregexenise'
ownfunction = require './ownfunction'
util = require './util'

clean_ast = (ast) ->
  estraverse.traverse(ast, {
    leave: (node) ->
      delete node.scope
      delete node.objType
  })

dumbifyAST = (ast, opt = {}) ->
  ast = basicTransforms ast
  if opt.requireObliteratinator isnt false
    ast = requireObliteratinator ast, {
      filename: opt.filename or '',
      transformRequiredModule: basicTransforms
    }
    clean_ast ast
  if opt.deregexenise isnt false
    ast = deregexenise ast
    clean_ast ast
  if opt.typeConversions isnt false
    typeConversions(ast, opt.typeConversions or {})
    clean_ast ast
  if opt.mainify isnt false
    mainify(ast, opt.mainify or {})
    clean_ast ast
  if opt.thatter isnt false
    thatter ast
    clean_ast ast
  if opt.depropinator isnt false
    depropinator ast
    clean_ast ast
  if opt.declosurify isnt false  # this one is not really a pass, it's a pre-declosurify operation
    ownfunction ast
    clean_ast ast
    declosurify ast
    clean_ast ast
  if opt.topmost isnt false
    topmost ast
    clean_ast ast
  if opt.bindify isnt false
    bindify ast  # mutate ast
    clean_ast ast
  isValid = astValidator ast
  if isValid != true
    throw isValid
  return ast

dumbify = (js, opt = {}) ->
  mayContainRequire = /require\s*?\(/m.test js
  ast = parse(js, opt.filename)
  if mayContainRequire is false
    opt.requireObliteratinator = false
  ast = dumbifyAST ast, opt
  return escodegen.generate ast, { comment: true }

module.exports = dumbify
module.exports.dumbify = dumbify
module.exports.dumbifyAST = dumbifyAST
module.exports.enableTestMode = util.enableTestMode
