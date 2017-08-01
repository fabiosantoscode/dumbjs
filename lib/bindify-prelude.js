module.exports =
`function BIND(func, closure) {
    return function BOUND() {
      return func.apply(this, [closure].concat([].slice.call(arguments)))
    }
}
`
