
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

