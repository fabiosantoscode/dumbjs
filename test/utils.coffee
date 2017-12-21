
dumbjs = require '../lib'
esprima = require 'esprima'
estraverse = require 'estraverse'
ok = require 'assert'
escodegen = require 'escodegen'

parse = (s) ->
  if typeof s is 'string'
    esprima.parse(s)
  else
    s

generate_if_needed = (s) ->
  if typeof s is 'string'
    s
  else
    escodegen.generate(s)

clean_ast = (ast) ->
  estraverse.traverse(ast, {
    leave: (node) ->
      delete node.scope
      delete node.objType
  })
  return ast

exports.jseq = jseq = (a, b, msg) ->
  try
    s_a = noWs(generate_if_needed(a))
    s_b = noWs(generate_if_needed(b))
  catch e
    ok.deepEqual(clean_ast(parse(a)), clean_ast(parse(b)), msg)
    ok false
    return
  ok.equal(s_a, s_b, msg)

exports.noWs = noWs = (s) ->
  s.replace(/(\s|\n)+/gm, ' ').replace(/\s*;\s*$/,'').trim()

exports.test = (
  before,
  fn,
  after,
) ->
  code1 = parse before
  ret = fn code1
  if !ret
    ret = code1  # it mutated!
  jseq ret, after

exports.checkOutput = (
  before,
  after,
  options
) ->
  compiled = dumbjs(before, options)
  jseq after, compiled

