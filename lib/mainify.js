

module.exports = function (ast, options) {
  if (!options) options = {}
  if (!options.prepend) options.prepend = []
  if (!options.append) options.append = []

  ast.body = [
    {
      type: "FunctionDeclaration",
      id: { type: "Identifier", name: "main" },
      params: [],
      defaults: [],
      body: {
        type: "BlockStatement",
        body: options.prepend.concat(ast.body).concat(options.append),
      }
    }
  ]
}
