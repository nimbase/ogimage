## Custom split-hero layout on a raw canvas (the escape hatch).
##
## Usage (from the package root):
##   `clue build examples/custom.nim --out:/tmp/ogcustom && /tmp/ogcustom [outDir]`
##
## `OgImage` only carries fonts/theme here; `render` is never
## called. `layout` computes the absolute boxes (page -> row of
## text column + image panel, column of badge/title/desc/footer),
## and everything else is direct `nvg` calls with spans as the
## Layer-0 text primitive.

import std/os
import std/strutils
import ogimage

const photoFile = "1230420.jpeg"
const boldFile = "Roboto-Bold.ttf"
const regularFile = "Roboto-Regular.ttf"

proc repoLayout(): tuple[data, outDir: string] =
  for d in ["tests/data", "../tests/data", "../../tests/data",
      "packages/ogimage/tests/data"]:
    if fileExists(d / photoFile):
      return (d, d.parentDir().parentDir() / "examples" / "out")
  ("tests/data", "examples/out")

proc textOpts(w, h: float64, maxLines: int): TextBoxOpts =
  TextBoxOpts(maxW: w, boxH: h, ha: thaLeft, va: tvaTop, wrap: true,
    overflow: toEllipsis, fit: tfNone, maxLines: maxLines,
    ellipsis: "...")

proc main(outDir, dataDir: string) =
  createDir(outDir)
  # Theme + fonts ride on a plain OgImage; no preset layout runs.
  var og = newOgImage(
    @[plain("Ship "), strong(fg("faster", rgb(56, 189, 248))),
      plain(" with pure Nim")],
    @[plain("Fixed sizes, ellipsis trimming, and named presets. No browser, no native deps.")],
    opDark)
  og.content.badge = "nimbase"
  og.content.footer = @[footerItem("@nimbase/ogimage"),
    footerItem("MIT")]
  let bold = dataDir / boldFile
  let regular = dataDir / regularFile
  if fileExists(bold):
    og.fontTitlePath = bold
    og.fontStrongPath = bold
  if fileExists(regular):
    og.fontBodyPath = regular

  let th = themeForPreset(og.preset, og.accent, og.hasAccent)
  let c = newCustomCanvas(1200, 630)
  let (titleId, bodyId) = ensureFonts(c, og)

  # Page -> row: 720px text column, 480px image panel.
  let cols = ogBox(0, 0, 1200, 630).splitRow(@[720.0, 480.0])
  let textCol = cols[0].inset(80.0, 62.0)
  let panel = cols[1]

  c.clear(th.pageBg)

  # Full-height image panel, manual cover-fit into its box.
  let photo = dataDir / photoFile
  var painted = false
  if fileExists(photo):
    let id = c.createImageFile(photo, {})
    if id != 0:
      let (iw, ih, ok) = c.imageSize(id)
      if ok and iw > 0 and ih > 0:
        let s = max(panel.w / float64(iw), panel.h / float64(ih))
        let dw = float64(iw) * s
        let dh = float64(ih) * s
        let ox = panel.x + (panel.w - dw) * 0.5
        let oy = panel.y + (panel.h - dh) * 0.5
        c.beginPath()
        c.rect(panel.x, panel.y, panel.w, panel.h)
        c.setFillPaint(c.imagePattern(ox, oy, dw, dh, 0.0, id, 1.0))
        c.fill()
        painted = true
  if not painted:
    c.beginPath()
    c.rect(panel.x, panel.y, panel.w, panel.h)
    c.setFillColor(rgb(30, 27, 75))
    c.fill()

  # Text column -> fixed rows: badge, title, desc, footer.
  let rows = textCol.splitColumn(@[44.0, 260.0, 100.0, 36.0],
    gap = 22.0)

  # Badge pill.
  c.setFontFaceId(bodyId)
  c.setFontSize(th.badgeSize)
  c.setLineHeight(1.2)
  let bm = c.measureTextBox(0, 0, og.content.badge, TextBoxOpts(
    maxW: rows[0].w, boxH: 44.0, ha: thaLeft, va: tvaTop,
    wrap: false, overflow: toEllipsis, fit: tfNone, maxLines: 1,
    ellipsis: "..."))
  let pillW = min(rows[0].w, bm.advance + 48.0)
  c.beginPath()
  c.roundedRect(rows[0].x, rows[0].y, pillW, 44.0, 22.0)
  c.setFillColor(th.badgeBg)
  c.fill()
  c.setFillColor(th.badgeColor)
  discard c.fillTextBox(rows[0].x, rows[0].y, og.content.badge,
    TextBoxOpts(maxW: pillW, boxH: 44.0, ha: thaCenter,
      va: tvaMiddle, wrap: false, overflow: toEllipsis,
      fit: tfNone, maxLines: 1, ellipsis: "..."))

  # Accent tick above the title: pure absolute decoration.
  c.beginPath()
  c.rect(rows[1].x, rows[1].y - 16.0, 64.0, 6.0)
  c.setFillColor(th.accent)
  c.fill()

  # Styled title via spans, clamped to 3 lines with "...".
  let strongF = loadFace(og.fontStrongPath, og.strongFaceIndex)
  let emF = loadFace(og.fontEmPath, og.emFaceIndex)
  c.setFontFaceId(titleId)
  c.setFontSize(th.titleSize)
  c.setLineHeight(1.12)
  c.setTextAlign(thaLeft, tvaTop)
  c.setFillColor(th.titleColor)
  let topts = textOpts(rows[1].w, 260.0, th.titleMaxLines)
  var tmp = toTextSpans(og.content.titleSegs, strongF, emF,
    th.accent)
  if c.measureSpanBox(0, 0, tmp.text, tmp.spans,
      topts).lineCount > th.titleMaxLines:
    let trimmed = c.ellipsizeToLines(tmp.text, topts)
    var cutBytes = trimmed.len
    if trimmed.endsWith(topts.ellipsis):
      cutBytes = trimmed.len - topts.ellipsis.len
    tmp = toTextSpans(trimSegs(og.content.titleSegs, cutBytes),
      strongF, emF, th.accent)
  discard c.fillSpanBox(rows[1].x, rows[1].y, tmp.text, tmp.spans,
    topts)

  # Plain description, clamped to 2 lines.
  c.setFontFaceId(bodyId)
  c.setFontSize(th.descSize)
  c.setLineHeight(1.4)
  c.setTextAlign(thaLeft, tvaTop)
  c.setFillColor(th.descColor)
  let dopts = textOpts(rows[2].w, 100.0, th.descMaxLines)
  let desc = c.ellipsizeToLines(segmentsText(og.content.descSegs),
    dopts)
  discard c.fillTextBox(rows[2].x, rows[2].y, desc, dopts)

  # Footer items as one hand-spaced row on a shared baseline.
  c.setFontFaceId(bodyId)
  c.setFontSize(th.siteSize)
  c.setLineHeight(1.2)
  c.setFillColor(th.siteColor)
  let probe = c.textSpanBounds(0, 0, "Ag", newSeq[TextSpan](0),
    TextBoxOpts(maxW: rows[3].w, boxH: 36.0, ha: thaLeft,
      va: tvaBaseline, wrap: false, overflow: toVisible,
      fit: tfNone, maxLines: 1, ellipsis: "..."))
  let baseY = rows[3].y - probe.y
  var fx = rows[3].x
  for i, it in og.content.footer:
    if i > 0:
      fx += 28.0
    let fopts = TextBoxOpts(maxW: rows[3].w - (fx - rows[3].x),
      boxH: 36.0, ha: thaLeft, va: tvaBaseline, wrap: false,
      overflow: toEllipsis, fit: tfNone, maxLines: 1,
      ellipsis: "...")
    discard c.fillTextBox(fx, baseY, it.label, fopts)
    fx += c.measureTextBox(0, 0, it.label, fopts).advance

  c.savePng(outDir / "og_custom.png")
  echo "wrote " & outDir / "og_custom.png"

when isMainModule:
  let (dataDir, defaultOut) = repoLayout()
  var outDir = defaultOut
  if paramCount() > 0:
    outDir = paramStr(1)
  main(outDir, dataDir)
