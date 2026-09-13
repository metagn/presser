import presser/[common, pages], os, strutils

proc main() =
  var config = Config(
    pagesDir: "pages",
    assetsDir: "assets",
    templatesDir: "assets/templates",
    outputDir: (when defined(testrun): "output" else: "public"),
    redirectOutputs:
      case getEnv("SITE_HOST").toLowerAscii
      of "firebase": {Firebase}
      of "cloudflare": {Cloudflare}
      of "githubpages": {} # githubPages
      else: {Firebase, Cloudflare} # all kinds
  )

  copyDir(config.pagesDir, config.outputDir)
  copyDir(config.assetsDir, config.outputDir / config.assetsDir)
  
  pipeline(config):
    var
      pages: Pages

when isMainModule: main()
