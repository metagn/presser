import ../common, templates, page_margrave

type
  PageKind* = enum
    pkAsset, pkMargrave

proc processPage*(kind: PageKind, path: string, templates: var Templates, config: Config) =
  case kind
  of pkAsset:
    # leave in place
    discard
  of pkMargrave:
    processMargravePage(path, templates, config)
