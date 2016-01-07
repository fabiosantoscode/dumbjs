exports.nameSluginator = (prefix = '_') ->
  sluginator = (name) ->
    prefix + name.replace(/./g, (char) ->
      if not /[a-zA-Z0-9_]/.test(char)
        return ''
      return char
    )
  _nameCounter = 0
  _namesUsed = []
  generateName = (name) ->
    if name
      name = sluginator name
      if name not in _namesUsed
        _namesUsed.push(name)
        return name
    return "#{prefix}#{_nameCounter++}"

  return generateName

