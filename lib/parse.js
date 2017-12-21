'use strict'

const esprima = require('esprima')
const parseError = require('parse-error')

const esprimaOpts = {
  sourceType: 'module',
  ecmaVersion: 6,
  allowReturnOutsideFunction: true,
  allowHashBang: true,
  locations: true,
  attachComment: true,
}

// Stolen from https://github.com/substack/node-syntax-error/blob/master/index.js
// And modified for esprima
function ParseError (err, line, column, src, file) {
  SyntaxError.call(this);

  this.message = err.message.replace(/\s+\(\d+:\d+\)$/, '');

  this.line = line
  this.column = column

  this.stack = '\n'
    + (file || '(anonymous file)')
    + ':' + this.line
    + '\n'
    + src.split('\n')[this.line - 1]
    + '\n'
    + Array(this.column).join(' ') + '^'
    + '\n'
    + 'ParseError: ' + this.message
  ;
}

ParseError.prototype = Object.create(SyntaxError.prototype);

ParseError.prototype.toString = function () {
  return this.annotated;
};

ParseError.prototype.inspect = function () {
  return this.annotated;
};

function indexToColumn(index, lineNumber, src) {
  if (lineNumber <= 1) {
    return index
  }
  const linesBefore = src.split(/\n/g, lineNumber - 1).map(x => x + '\n')
  const charactersBeforeThisLine = linesBefore.join('\n').length
  return index - charactersBeforeThisLine
}

module.exports = function parse(js, filename) {
  try {
    return esprima.parse(js, esprimaOpts)
  } catch(e) {
    throw new ParseError(e, e.lineNumber, indexToColumn(e.index, e.lineNumber, js), js, filename)
  }
}
