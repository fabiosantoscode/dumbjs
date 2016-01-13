

module.exports = (ast, { prepend = [], append = [] } = {}) ->
  ast.body = [
    {
      type: "FunctionDeclaration",
      id: { type: "Identifier", name: "main" },
      params: [],
      defaults: [],
      body: {
        type: "BlockStatement",
        body: prepend.concat(ast.body).concat(append),
      }
    }
  ]

