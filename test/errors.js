'use strict'

const ok = require('assert')
const dumbjs = require('../lib')

describe('errors', () => {
  it('are pretty-printed along with the source code', () => {
    try{
      dumbjs('function foo(){\nsyntax error\n}', { filename: 'foo.js' })
    } catch(syntaxError) {
      ok(/foo.js:2/.test(syntaxError.stack))
      ok(/syntax error/.test(syntaxError.stack))
    }
  })
})

