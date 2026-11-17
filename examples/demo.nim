## Render one sample card per preset into examples/out/.
##
## Usage (from the package root):
##   `clue build examples/demo.nim && ./demo [outDir]`
## Asset lookup probes upward so it also works when run from
## `examples/` or `examples/out/`. Fonts fall back to the library
## system default when the vendored files are missing.

import std/os
import ogimage

const photoFile = "1230420.jpeg"
const bgPhotoFile = "pexels-marie-gaebel-2164524425-40393792.jpeg"
const boldFile = "Roboto-Bold.ttf"
const regularFile = "Roboto-Regular.ttf"

proc repoLayout(): tuple[data, outDir: string] =
  ## Find vendored assets from common working directories so the
  ## demo works run from the package root, `examples/`, or below.
  for d in ["tests/data", "../tests/data", "../../tests/data",
      "packages/ogimage/tests/data"]:
    if fileExists(d / photoFile):
      return (d, d.parentDir().parentDir() / "examples" / "out")
  ("tests/data", "examples/out")

proc applyRepo(og: var OgImage, dataDir: string) =
  og.content.repo = "@nimbase/ogimage"
  og.repoIconDark = dataDir / "github-white.png"
  og.repoIconLight = dataDir / "github-black.png"

proc sample(preset: OgPreset, dataDir: string): OgImage =
  result = newOgImage(
    "Pure-Nim OpenGraph images in one call",
    "Fixed sizes, ellipsis trimming, and named presets. No browser, no native deps.",
    preset)
  result.content.badge = "nimbase"
  result.applyRepo(dataDir)
  let bold = dataDir / boldFile
  let regular = dataDir / regularFile
  if fileExists(bold):
    result.fontTitlePath = bold
  if fileExists(regular):
    result.fontBodyPath = regular

proc applyFonts(og: var OgImage, dataDir: string) =
  let bold = dataDir / boldFile
  let regular = dataDir / regularFile
  if fileExists(bold):
    og.fontTitlePath = bold
  if fileExists(regular):
    og.fontBodyPath = regular

proc russianSample(dataDir: string): OgImage =
  result = newOgImage(
    "OpenGraph-изображения на чистом Nim",
    "Фиксированные размеры, обрезка с многоточием и именованные темы. Без браузера и нативных зависимостей.",
    opLight)
  result.content.badge = "нимбейс"
  result.applyRepo(dataDir)
  result.applyFonts(dataDir)

proc hebrewFontPair(): tuple[title, body: string] =
  ## A single font covering Hebrew + Latin (mixed-direction text
  ## needs one covering font; per-run fallbacks shape in logical
  ## order). Prefers Noto Sans Hebrew, then Arial Unicode.
  const notoBold = "/usr/share/fonts/truetype/noto/NotoSansHebrew-Bold.ttf"
  const notoRegular = "/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf"
  const arialUni = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
  if fileExists(notoBold) and fileExists(notoRegular):
    return (notoBold, notoRegular)
  if fileExists(arialUni):
    return (arialUni, arialUni)
  ("", "")

proc hebrewFallbacks(dataDir: string): seq[string] =
  ## Last-resort Hebrew coverage when no single covering font
  ## exists (same-direction runs only).
  result = @[]
  for p in ["/System/Library/Fonts/ArialHB.ttc",
      "/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf"]:
    if fileExists(p):
      result.add(p)

proc hebrewSample(dataDir: string): OgImage =
  ## RTL card: visual order and right alignment come from nvg's
  ## bidi shaping plus the `thaRight` override.
  result = newOgImage(
    "תמונות OpenGraph ב־Nim טהור",
    "גדלים קבועים, חיתוך עם שלוש נקודות וערכות מוכנות. בלי דפדפן ובלי תלויות.",
    opGradient)
  result.content.badge = "nimbase"
  result.applyRepo(dataDir)
  result.hasAlign = true
  result.align = thaRight
  let (ht, hb) = hebrewFontPair()
  if ht != "":
    result.fontTitlePath = ht
    result.fontBodyPath = hb
  else:
    echo "warning: no single Hebrew font found; card may show tofu"
    result.fallbackFontPaths = hebrewFallbacks(dataDir)
    result.applyFonts(dataDir)

proc longSample(preset: OgPreset, dataDir: string): OgImage =
  ## Overflowing copy: title clamps to 3 lines, description to 2,
  ## both trimmed with "...".
  result = newOgImage(
    "To be, or not to be, that is the question: whether 'tis nobler in the mind to suffer the slings and arrows of outrageous fortune",
    "All the world's a stage, and all the men and women merely players: they have their exits and their entrances, and one man in his time plays many parts, his acts being seven ages.",
    preset)
  result.content.badge = "shakespeare"
  result.applyRepo(dataDir)
  let bold = dataDir / boldFile
  let regular = dataDir / regularFile
  if fileExists(bold):
    result.fontTitlePath = bold
  if fileExists(regular):
    result.fontBodyPath = regular

proc richSample(dataDir: string): OgImage =
  ## Segment-styled copy: strong/em runs, fg accent, a link and a
  ## marker highlight, all without markup.
  result = newOgImage(
    @[plain("Ship "), strong(fg("faster", rgb(56, 189, 248))),
      plain(" with pure Nim")],
    @[plain("Fixed sizes, "), em(plain("ellipsis trimming")),
      plain(", and "), link(plain("named presets"),
        "https://github.com/nimbase/ogimage"),
      plain(" with "),
      bg(fg(plain("zero native deps"), rgb(15, 23, 42)),
        rgb(253, 224, 71)), plain(".")],
    opDark)
  result.content.badge = "nimbase"
  result.applyRepo(dataDir)
  result.applyFonts(dataDir)
  result.fontStrongPath = dataDir / boldFile
  let italic = dataDir / "Roboto-Italic.ttf"
  if fileExists(italic):
    result.fontEmPath = italic

proc main(outDir, dataDir: string) =
  createDir(outDir)
  let photo = dataDir / photoFile
  if not fileExists(photo):
    echo "warning: photo not found: " & photo & " (photo card falls back)"
  for (preset, name) in [(opDark, "dark"), (opLight, "light"),
      (opGradient, "gradient"), (opPhoto, "photo"),
      (opMinimal, "minimal"), (opBrand, "brand")]:
    var og = sample(preset, dataDir)
    if name == "photo":
      og.content.photoPath = photo
      og.content.description = "The photo avatar shares the headline row, while this description stretches across the full card width below."
    og.savePng(outDir / ("og_" & name & ".png"))
    echo "wrote " & outDir / ("og_" & name & ".png")
  for (preset, name) in [(opDark, "long_dark"),
      (opMinimal, "long_minimal")]:
    var og = longSample(preset, dataDir)
    og.savePng(outDir / ("og_" & name & ".png"))
    echo "wrote " & outDir / ("og_" & name & ".png")
  for (name, maker) in [("russian", russianSample),
      ("hebrew", hebrewSample)]:
    var og = maker(dataDir)
    og.savePng(outDir / ("og_" & name & ".png"))
    echo "wrote " & outDir / ("og_" & name & ".png")
  var rich = richSample(dataDir)
  rich.savePng(outDir / "og_rich.png")
  echo "wrote " & outDir / "og_rich.png"
  var retina = sample(opDark, dataDir)
  retina.scale = 2.0
  retina.savePng(outDir / "og_retina.png")
  echo "wrote " & outDir / "og_retina.png"
  var missing = sample(opDark, dataDir)
  missing.content.photoPath = "/nonexistent/photo.png"
  missing.content.logoPath = "/nonexistent/logo.png"
  missing.repoIconDark = "/nonexistent/dark.png"
  missing.repoIconLight = "/nonexistent/light.png"
  missing.savePng(outDir / "og_missing.png")
  echo "wrote " & outDir / "og_missing.png"
  for (name, fit, pos) in [("bg_cover", bgCover, bgPosCenter()),
      ("bg_contain", bgContain, bgPosCenter()),
      ("bg_fill", bgFill, bgPosCenter()),
      ("bg_pos", bgCover, bgPosPx(0.0, 0.0))]:
    var og = sample(opDark, dataDir)
    og.hasBackground = true
    let bgPhoto = dataDir / bgPhotoFile
    if fileExists(bgPhoto):
      og.background = imageBackgroundEx(bgPhoto, fit, pos)
    else:
      echo "warning: bg photo not found: " & bgPhoto & " (solid fallback)"
      og.background = solidBackground(rgb(30, 27, 75))
    og.savePng(outDir / ("og_" & name & ".png"))
    echo "wrote " & outDir / ("og_" & name & ".png")
  var bgGrad = sample(opDark, dataDir)
  bgGrad.hasBackground = true
  bgGrad.background = gradientBackground(rgb(79, 70, 229),
    rgb(124, 58, 237))
  bgGrad.savePng(outDir / "og_bg_gradient.png")
  echo "wrote " & outDir / "og_bg_gradient.png"

when isMainModule:
  let (dataDir, defaultOut) = repoLayout()
  var outDir = defaultOut
  if paramCount() > 0:
    outDir = paramStr(1)
  main(outDir, dataDir)
