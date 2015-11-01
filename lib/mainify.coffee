

module.exports = (ast) ->
  ast.body = [
    {
      type: "FunctionDeclaration",
      id: { type: "Identifier", name: "main" },
      params: [],
      defaults: [],
      body: {
        type: "BlockStatement",
        body: ast.body,
      }
    }
  ]

