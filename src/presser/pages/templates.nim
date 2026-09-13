import std/[locks, tables]

type Templates* = object
  bodyLock*: Lock
  bodies* {.guard: bodyLock.}: Table[string, string]
  defaultTemplate*: tuple[path, content: string]

proc getTemplate*(templates: var Templates, name: string): lent string =
  withLock templates.bodyLock:
    if not templates.bodies.hasKey(name):
      templates.bodies[name] = readFile(name)
    result = templates.bodies[name]

proc initTemplates*(default: string): Templates =
  result = Templates()
  initLock(result.bodyLock)
  result.defaultTemplate = (path: default, content: result.getTemplate(default))

proc clearTemplates*(templates: var Templates) =
  reset(templates.defaultTemplate)
  withLock templates.bodyLock:
    templates.bodies.clear()
  deinitLock(templates.bodyLock)
