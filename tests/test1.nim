import std/os
import std/strutils
import std/unittest
import ogimage

proc testFontPath(): string =
  ## Vendored Roboto, relative to the package root (`clue test`
  ## runs from there).
  let candidates = @[
    "tests/data/Roboto-Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
  ]
  for c in candidates:
    if fileExists(c):
      return c
  ""

proc makeOg(preset = opDark): OgImage =
  let f = testFontPath()
  result = newOgImage("Ship faster with pure Nim",
    "A tiny library that renders OpenGraph cards with zero native deps.",
    preset)
  result.content.badge = "nimbase"
  result.content.site = "nimbase.dev"
  if f != "":
    result.fontTitlePath = f
    result.fontBodyPath = f

suite "ogimage construction":
  test "defaults are 1200x630":
    let og = newOgImage("T", "D")
    check og.width == 1200
    check og.height == 630
    check og.preset == opDark

  test "background constructors":
    check solidBackground(rgb(1, 2, 3)).kind == bgSolid
    check gradientBackground(rgb(0, 0, 0), rgb(1, 1, 1)).kind == bgGradient
    check imageBackground("x.png").kind == bgImage
    check imageBackground("x.png").overlayAlpha == 0.55
    check imageBackground("x.png").overlayAngleDeg == -90.0
    check imageBackgroundEx("x.png", bgCover, bgPosCenter(),
      overlayAlpha = 0.5, overlayAngleDeg = 0.0).overlayAngleDeg == 0.0
    check imageBackground("x.png").fit == bgCover
    check imageBackground("x.png").pos.centered
    check imageBackgroundEx("x.png", bgContain,
      bgPosPx(10.0, 20.0)).fit == bgContain
    let p = imageBackgroundEx("x.png", bgCover, bgPosPx(10.0, 20.0)).pos
    check not p.centered
    check p.x == 10.0
    check p.y == 20.0

suite "ogimage themes":
  test "presets resolve distinct pages":
    let dark = themeForPreset(opDark, rgb(0, 0, 0), false)
    let light = themeForPreset(opLight, rgb(0, 0, 0), false)
    check dark.pageBg != light.pageBg
    check dark.titleColor != light.titleColor

  test "custom accent is honored":
    let th = themeForPreset(opDark, rgb(1, 2, 3), true)
    check th.accent == rgb(1, 2, 3)

suite "ogimage spans":
  test "segment builders compose":
    let segs = @[plain("Ship "), strong(fg("faster", rgb(255, 0, 0))),
      em(link("docs", "https://nimbase.dev"))]
    check segmentsText(segs) == "Ship fasterdocs"
    let strongF = loadFace("tests/data/Roboto-Bold.ttf")
    let emF = loadFace("tests/data/Roboto-Italic.ttf")
    let (text, spans, bgs) =
      toTextSpans(segs, strongF, emF, rgb(0, 0, 255))
    check text == "Ship fasterdocs"
    check spans.len == 3
    check spans[1].font != nil
    check spans[1].hasColor
    check spans[1].color == rgb(255, 0, 0)
    check spans[2].font != nil
    check spans[2].decor == tdUnderline
    check spans[2].hasColor
    check spans[2].color == rgb(0, 0, 255)
    check bgs.len == 0

  test "bg ranges and trim keep styles":
    let segs = @[plain("ab"), bg(plain("cd"), rgb(0, 0, 0))]
    let (_, _, bgs) = toTextSpans(segs, nil, nil, rgb(0, 0, 0))
    check bgs.len == 1
    check bgs[0].first == 2
    check bgs[0].last == 4
    let cut = trimSegs(segs, 3)
    check segmentsText(cut) == "abc"
    check cut.len == 2
    check cut[1].hasBg

  test "segment title and description render":
    var og = makeOg()
    og.content.titleSegs = @[plain("Ship "),
      strong(fg("faster", rgb(56, 189, 248)))]
    og.content.descSegs = @[plain("Zero "), em(plain("native")),
      link(plain(" deps"), "https://nimbase.dev"),
      bg(fg(plain("!"), rgb(15, 23, 42)), rgb(253, 224, 71))]
    check encodePng(og).len > 100
    og.fontStrongPath = "tests/data/Roboto-Bold.ttf"
    og.fontEmPath = "tests/data/Roboto-Italic.ttf"
    check encodePng(og).len > 100
    og.content.titleSegs = @[plain("Long ".repeat(30))]
    check encodePng(og).len > 100

suite "ogimage render":
  test "invalid dimensions raise":
    var og = makeOg()
    og.width = 0
    expect OgError:
      discard render(og)

  test "renders at the requested size":
    let og = makeOg()
    let c = render(og)
    check c.width == 1200
    check c.height == 630

  test "png bytes carry a PNG signature":
    let bytes = encodePng(makeOg())
    check bytes.len > 100
    check bytes[0] == 137u8
    check bytes[1] == 80u8
    check bytes[2] == 78u8
    check bytes[3] == 71u8

  test "long copy ellipsizes instead of raising":
    var og = makeOg()
    og.content.title = "This is a very long title ".repeat(20)
    og.content.description = "A very long description ".repeat(30)
    let bytes = encodePng(og)
    check bytes.len > 100

  test "overflow copy is pre-trimmed with an ellipsis marker":
    let og = makeOg()
    let c = newCanvas(1200, 630)
    let (titleId, _) = ensureFonts(c, og)
    c.setFontFaceId(titleId)
    c.setFontSize(76.0)
    c.setLineHeight(1.12)
    let o = TextBoxOpts(maxW: 1040.0, boxH: 260.0, ha: thaLeft,
      va: tvaTop, wrap: true, overflow: toEllipsis, fit: tfNone,
      maxLines: 3, ellipsis: "...")
    check c.ellipsizeToLines("Short title", o) == "Short title"
    let long = "To be, or not to be, that is the question: ".repeat(10)
    let trimmed = c.ellipsizeToLines(long, o)
    check trimmed.endsWith("...")
    var probe = o
    probe.maxLines = 0
    check c.measureTextBox(0, 0, trimmed, probe).lineCount <= 3

  test "every preset renders":
    for preset in [opDark, opLight, opGradient, opPhoto, opMinimal,
        opBrand]:
      let bytes = encodePng(makeOg(preset))
      check bytes.len > 100

  test "explicit backgrounds render":
    var og = makeOg()
    og.hasBackground = true
    og.background = solidBackground(rgb(20, 30, 40))
    check encodePng(og).len > 100
    og.background = gradientBackground(rgb(79, 70, 229),
      rgb(124, 58, 237))
    check encodePng(og).len > 100
    og.background = imageBackground("/nonexistent/bg.png")
    check encodePng(og).len > 100
    og.background = imageBackground("tests/data/1230420.jpeg")
    check encodePng(og).len > 100
    og.background = imageBackgroundEx("tests/data/1230420.jpeg",
      bgContain)
    check encodePng(og).len > 100
    og.background = imageBackgroundEx("tests/data/1230420.jpeg", bgFill)
    check encodePng(og).len > 100
    og.background = imageBackgroundEx("tests/data/1230420.jpeg",
      bgCover, bgPosPx(0.0, 0.0))
    check encodePng(og).len > 100

  test "background fit and position change the output":
    proc bgOg(fit: OgBgFit, pos: OgBgPos): OgImage =
      result = makeOg()
      result.hasBackground = true
      result.background = imageBackgroundEx("tests/data/1230420.jpeg",
        fit, pos, overlayAlpha = 0.0)
    let cover = encodePng(bgOg(bgCover, bgPosCenter()))
    let contain = encodePng(bgOg(bgContain, bgPosCenter()))
    let fill = encodePng(bgOg(bgFill, bgPosCenter()))
    let shifted = encodePng(bgOg(bgCover, bgPosPx(0.0, 0.0)))
    check cover != contain
    check cover != fill
    check cover != shifted

  test "bg image scrim fades from tint to transparent":
    proc scrimOg(alpha: float64): OgImage =
      result = makeOg()
      result.hasBackground = true
      result.background = imageBackgroundEx(
        "tests/data/pexels-marie-gaebel-2164524425-40393792.jpeg",
        bgCover, bgPosCenter(), overlayAlpha = alpha)
    check encodePng(scrimOg(0.55)) != encodePng(scrimOg(0.0))

  test "segment bg highlight does not leak into ink":
    var og = makeOg()
    og.content.titleSegs = @[plain("AAAA"),
      bg(plain("BBBB"), rgb(253, 224, 71))]
    og.content.descSegs = @[]
    let c = render(og)
    var found = false
    for y in 130 ..< 260:
      for x in 80 ..< 600:
        let px = c.surface.getPixel(x, y)
        if px.r > 0.5:
          # First ink is the plain run: white, not highlight yellow.
          check px.b > 0.8
          found = true
          break
      if found:
        break
    check found

  test "missing logo is skipped, not fatal":
    var og = makeOg()
    og.content.logoPath = "/nonexistent/logo.png"
    check encodePng(og).len > 100

  test "photo panel renders and missing photo falls back":
    var og = makeOg()
    og.content.photoPath = "tests/data/1230420.jpeg"
    check encodePng(og).len > 100
    og.content.photoPath = "/nonexistent/photo.png"
    check encodePng(og).len > 100

  test "missing photo draws a labeled placeholder":
    var og = makeOg()
    og.content.photoPath = "/nonexistent/photo.png"
    let c = render(og)
    # Inside the 128x128 photo box, above the centered label.
    let px = c.surface.getPixel(1010, 140)
    check abs(px.r - 209.0 / 255.0) < 0.03
    check abs(px.g - 213.0 / 255.0) < 0.03
    check abs(px.b - 219.0 / 255.0) < 0.03

  test "footer items render with icons, counters and fallback":
    var og = makeOg()
    og.content.site = ""
    og.content.footer = @[footerItem("@nimbase/ogimage",
      "tests/data/github-white.png", "tests/data/github-black.png"),
      footerItem("1.2k"), footerItem("MIT")]
    check encodePng(og).len > 100
    og.preset = opLight
    check encodePng(og).len > 100
    og.content.footer = @[footerItem("x", "/nonexistent.png",
      "/nonexistent.png")]
    check encodePng(og).len > 100
    og.content.footer = @[]
    og.content.site = "nimbase.dev"
    check encodePng(og).len > 100

  test "footer icon centers on the label text ink":
    # The mark is an inline box child (parent-driven alignment), so
    # its ink center must ride the label's ink center instead of
    # a hand-positioned box offset.
    var og = makeOg()
    og.content.site = ""
    og.content.footer = @[footerItem("@nimbase/ogimage",
      "tests/data/github-white.png", "tests/data/github-black.png")]
    let c = render(og)
    proc inkRows(c: Canvas, x0, x1: int): tuple[found: bool,
        cy: float64] =
      var top = -1
      var bottom = -1
      for y in 500 ..< 610:
        for x in x0 ..< x1:
          if c.surface.getPixel(x, y).r > 0.5:
            if top < 0:
              top = y
            bottom = y
            break
      if top < 0:
        (false, 0.0)
      else:
        (true, (float64(top) + float64(bottom)) * 0.5)
    let icon = inkRows(c, 60, 100)
    let text = inkRows(c, 110, 500)
    check icon.found
    check text.found
    check abs(icon.cy - text.cy) <= 2.0

  test "footer items share one baseline":
    # Icon rows lay out taller ink than text-only rows; every item
    # must still sit on the same baseline.
    var og = makeOg()
    og.content.site = ""
    og.content.footer = @[footerItem("ABC",
      "tests/data/github-white.png", "tests/data/github-black.png"),
      footerItem("DEF")]
    let c = render(og)
    proc labelCy(c: Canvas, x0, x1: int): float64 =
      var top = -1
      var bottom = -1
      for y in 500 ..< 610:
        for x in x0 ..< x1:
          if c.surface.getPixel(x, y).r > 0.5:
            if top < 0:
              top = y
            bottom = y
            break
      check top >= 0
      (float64(top) + float64(bottom)) * 0.5
    check abs(labelCy(c, 115, 175) - labelCy(c, 195, 260)) <= 1.0

  test "fitted icon uploads near display size, missing fails":
    let c = newCanvas(64, 64)
    # 512px source drawn at 28.8px (the footer icon): 2x oversample.
    let id = c.createFittedImage("tests/data/github-white.png",
      28.8, 28.8)
    let (w, h, ok) = c.imageSize(id)
    check ok
    check w == 58
    check h == 58
    # A target larger than the source uploads the original.
    let big = c.createFittedImage("tests/data/github-white.png",
      400.0, 400.0)
    let (bw, bh, bok) = c.imageSize(big)
    check bok
    check bw == 512
    check bh == 512
    check c.createFittedImage("/nonexistent.png", 28.8, 28.8) == 0
    check c.createFittedImage("tests/data/brand-github.svg",
      28.8, 28.8) == 0 # no SVG decoder: SVG never becomes an image
    check c.createFittedImage("tests/data/github-white.png",
      0.0, 28.8) == 0

  test "fallback fonts register without breaking render":
    const heb = "/System/Library/Fonts/ArialHB.ttc"
    if not fileExists(heb):
      skip()
    var og = makeOg()
    og.content.title = "תמונות OpenGraph ב־Nim טהור"
    og.content.description = "גדלים קבועים, חיתוך עם שלוש נקודות."
    og.hasAlign = true
    og.align = thaRight
    og.fallbackFontPaths = @[heb]
    check encodePng(og).len > 100

  test "scale doubles output dimensions":
    var og = makeOg()
    og.scale = 2.0
    let bytes = encodePng(og)
    check bytes.len > 100
    proc u32be(b: openArray[uint8], at: int): int =
      (int(b[at]) shl 24) or (int(b[at+1]) shl 16) or
        (int(b[at+2]) shl 8) or int(b[at+3])
    check u32be(bytes, 16) == 2400
    check u32be(bytes, 20) == 1260

  test "savePng writes a file":
    let og = makeOg()
    let path = getTempDir() / "ogimage_test.png"
    og.savePng(path)
    check fileExists(path)
    check getFileSize(path) > 100

suite "ogimage layout":
  test "inset shrinks on all sides":
    let b = ogBox(0, 0, 1200, 630).inset(80.0, 62.0)
    check b.x == 80.0
    check b.y == 62.0
    check b.w == 1040.0
    check b.h == 506.0
    check ogBox(0, 0, 10, 10).inset(80.0).w == 0.0

  test "splitRow places absolute cells left to right":
    let cols = ogBox(0, 0, 1200, 630).splitRow(@[720.0, 480.0])
    check cols.len == 2
    check cols[0] == ogBox(0, 0, 720.0, 630)
    check cols[1] == ogBox(720.0, 0, 480.0, 630)
    let gapped = ogBox(0, 0, 100, 50).splitRow(@[30.0, 40.0],
      gap = 10.0)
    check gapped[0].x == 0.0
    check gapped[1].x == 40.0

  test "splitColumn stacks absolute cells top to bottom":
    let rows = ogBox(80, 62, 560, 506).splitColumn(
      @[44.0, 260.0, 100.0, 36.0], gap = 22.0)
    check rows.len == 4
    check rows[0].y == 62.0
    check rows[1].y == 62.0 + 44.0 + 22.0
    check rows[3].y + rows[3].h == 62.0 + 506.0
    for r in rows:
      check r.x == 80.0
      check r.w == 560.0

  test "flex splits share space proportionally":
    let cols = ogBox(0, 0, 1200, 630).splitRowFlex(@[3.0, 2.0])
    check cols.len == 2
    check abs(cols[0].w - 720.0) < 1e-9
    check abs(cols[1].w - 480.0) < 1e-9
    check cols[1].x == cols[0].x + cols[0].w
    let rows = ogBox(0, 0, 100, 106).splitColumnFlex(
      @[1.0, 1.0], gap = 6.0)
    check abs(rows[0].h - 50.0) < 1e-9
    check abs(rows[1].y - 56.0) < 1e-9
