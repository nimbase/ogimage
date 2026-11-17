## Font registration with optional user paths and a system default.
##
## `nvg` ships no fonts, so `ogimage` accepts optional
## `fontTitlePath`/`fontBodyPath` and otherwise searches well-known
## system locations plus `OGIMAGE_FONT_TITLE`/`OGIMAGE_FONT`. Tests
## and examples should pass explicit `.ttf` paths to stay
## deterministic across machines.

import std/os
import nvg
import ./types

export types

proc defaultTitleCandidates*(): seq[string] =
  result = @[]
  let envTitle = getEnv("OGIMAGE_FONT_TITLE")
  let envAny = getEnv("OGIMAGE_FONT")
  if envTitle != "":
    result.add(envTitle)
  if envAny != "":
    result.add(envAny)
  result.add("/System/Library/Fonts/Helvetica.ttc")
  result.add("/System/Library/Fonts/Supplemental/Arial Bold.ttf")
  result.add("/System/Library/Fonts/Supplemental/Arial.ttf")
  result.add("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")
  result.add("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
  result.add("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf")

proc defaultBodyCandidates*(): seq[string] =
  result = @[]
  let envBody = getEnv("OGIMAGE_FONT_BODY")
  let envAny = getEnv("OGIMAGE_FONT")
  if envBody != "":
    result.add(envBody)
  if envAny != "":
    result.add(envAny)
  result.add("/System/Library/Fonts/Helvetica.ttc")
  result.add("/System/Library/Fonts/Supplemental/Arial.ttf")
  result.add("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
  result.add("/usr/share/fonts/TTF/DejaVuSans.ttf")

proc ensureFallbacks*(c: Canvas, paths: openArray[string]) =
  ## Register `paths` as fallback faces for the current state, so
  ## glyphs missing from the title/body font (e.g. Hebrew alongside
  ## Roboto) still shape. Unknown files are skipped.
  var names: seq[string] = @[]
  for i, p in paths:
    if p == "":
      continue
    let nm = "og-fallback-" & $i
    try:
      if not fileExists(p):
        continue
    except CatchableError:
      continue
    if c.createFont(nm, p) != 0:
      names.add(nm)
  if names.len > 0:
    c.setFallbackFonts(names)

proc registerOne(c: Canvas, slot, path: string,
    faceIndex: int): int =
  if path == "":
    return 0
  try:
    if not fileExists(path):
      return 0
  except CatchableError:
    return 0
  c.createFont(slot, path, faceIndex)

proc ensureFonts*(c: Canvas, og: OgImage):
    tuple[titleId, bodyId: int] =
  ## Register title and body fonts, resolving defaults when the
  ## `OgImage` paths are empty. Raises `OgError` when no usable
  ## font is found.
  var titleId = registerOne(c, "og-title", og.fontTitlePath,
    og.titleFaceIndex)
  if titleId == 0:
    for cand in defaultTitleCandidates():
      titleId = registerOne(c, "og-title", cand, 0)
      if titleId != 0:
        break
  if titleId == 0:
    raise newException(OgError,
      "ogimage: no title font found; set fontTitlePath or OGIMAGE_FONT")

  let bodyPath = if og.fontBodyPath != "": og.fontBodyPath
    else: og.fontTitlePath
  let bodyFace = if og.fontBodyPath != "": og.bodyFaceIndex
    else: og.titleFaceIndex
  var bodyId = registerOne(c, "og-body", bodyPath, bodyFace)
  if bodyId == 0:
    for cand in defaultBodyCandidates():
      bodyId = registerOne(c, "og-body", cand, 0)
      if bodyId != 0:
        break
  if bodyId == 0:
    bodyId = titleId
  (titleId, bodyId)
