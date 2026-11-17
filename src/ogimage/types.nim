## Shared value types for the ogimage library.
##
## `OgImage` is the single input object: content plus presentation.
## Rendering lives in `ogimage/render`; presets in `ogimage/theme`.

import nvg
import ./spans

export nvg
export spans

type
  OgPreset* = enum
    opDark
      ## Dark card, light text, accent bar.
    opLight
      ## White card, dark ink.
    opGradient
      ## Full-bleed brand gradient, white ink.
    opPhoto
      ## Background photo with a dark overlay, white ink.
    opMinimal
      ## Centered, quiet, thin divider instead of an accent bar.
    opBrand
      ## Accent-driven gradient, white ink, centered.

  OgBgFit* = enum
    bgCover
      ## Scale to fill the canvas, cropping overflow
      ## (CSS `background-size: cover`).
    bgContain
      ## Scale to fit inside the canvas, letterboxing on the
      ## preset page color (CSS `background-size: contain`).
    bgFill
      ## Stretch to the exact canvas size, ignoring aspect ratio.

  OgBgPos* = object
    ## Where to place the background image. Either centered on
    ## both axes (`center center`) or an explicit top-left origin
    ## in user units (`px px`).
    case centered*: bool
    of true:
      discard
    of false:
      x*: float64
      y*: float64

  OgBackgroundKind* = enum
    bgSolid
    bgGradient
    bgImage

  OgBackground* = object
    ## Explicit background override. When `kind` is `bgImage` but
    ## `path` is empty or undecodable, render falls back to the
    ## preset solid.
    case kind*: OgBackgroundKind
    of bgSolid:
      color*: Color
    of bgGradient:
      fromColor*: Color
      toColor*: Color
      angleDeg*: float64
    of bgImage:
      path*: string
      tint*: Color
      overlayAlpha*: float64
      overlayAngleDeg*: float64
        ## Direction of the scrim gradient, in degrees (-90.0 =
        ## opaque at the bottom behind the description/footer,
        ## fading to transparent at the top). Same convention as
        ## `angleDeg`.
      fit*: OgBgFit
      pos*: OgBgPos

  OgFooterItem* = object
    ## One bottom-row item: an optional icon plus its label
    ## (handle, counter, caption — e.g. "@nimbase/ogimage", "1.2k",
    ## "MIT"). Any raster icon works; the dark/light paths pick the
    ## variant for the preset brightness.
    iconDark*: string
      ## Icon raster for dark presets; "" draws the label alone.
    iconLight*: string
      ## Icon raster for light presets; "" falls back to `iconDark`.
    label*: string

  OgContent* = object
    title*: string
    description*: string
    titleSegs*: seq[OgSeg]
      ## Rich title runs; when non-empty these win over `title`.
    descSegs*: seq[OgSeg]
      ## Rich description runs; when non-empty these win over
      ## `description`.
    badge*: string
      ## Small pill above the title. Empty hides it.
    site*: string
      ## Plain footer label, e.g. "nimbase.dev". Empty hides it.
      ## Ignored when `footer` items are set.
    footer*: seq[OgFooterItem]
      ## Bottom-row icon + label items (handles, counters, captions)
      ## laid out as one NVG flex row. Empty falls back to `site`.
    logoPath*: string
      ## Optional square-ish logo drawn in the top-right corner.
      ## Empty skips it, as does a set `photoPath` (the photo owns
      ## the right side).
    photoPath*: string
      ## Optional photo drawn as a `photoRadius` rounded square avatar
      ## sharing the headline row (like a profile pic). The
      ## description below keeps the full width. Empty or
      ## undecodable paths fall back to the full-width layout.

  OgTheme* = object
    ## Resolved drawing parameters for one render. Build with
    ## `themeForPreset`; fields are fixed sizes because body text
    ## uses ellipsis, never auto-shrink.
    titleSize*: float64
    descSize*: float64
    badgeSize*: float64
    siteSize*: float64
    onDark*: bool
      ## True when the preset background is dark (picks the light
      ## repo icon variant).
    titleColor*: Color
    descColor*: Color
    badgeBg*: Color
    badgeColor*: Color
    siteColor*: Color
    pageBg*: Color
      ## Fallback page color under photos/gradients.
    accent*: Color
    align*: TextHAlign
    padding*: float64
    radius*: float64
    titleMaxLines*: int
    descMaxLines*: int
    centered*: bool

  OgImage* = object
    width*: int
    height*: int
    content*: OgContent
    background*: OgBackground
    hasBackground*: bool
      ## When false the preset default background is used.
    preset*: OgPreset
    accent*: Color
    hasAccent*: bool
      ## When false the preset default accent is used.
    align*: TextHAlign
    hasAlign*: bool
      ## When true, overrides the preset alignment (e.g. `thaRight`
      ## for RTL text). Otherwise the preset alignment is used.
    scale*: float64
      ## Output scale factor (1.0 = 1200x630 px, 2.0 = retina
      ## 2400x1260 px). Layout stays in `width`x`height` user units.
      ## Values <= 0 fall back to 1.0.
    fontTitlePath*: string
      ## Empty resolves via `resolveTitleFont`.
    fontBodyPath*: string
      ## Empty falls back to the title font.
    fontStrongPath*: string
      ## Bold face for `strong` segments. Empty falls back to the
      ## layout font (a no-op when the base face is already bold).
    fontEmPath*: string
      ## Italic face for `em` segments. Empty falls back to the
      ## layout font. A bold-italic file here also covers
      ## `strong(em(...))` runs.
    strongFaceIndex*: int
    emFaceIndex*: int
    fallbackFontPaths*: seq[string]
      ## Optional fallback faces for glyphs missing from the title
      ## or body font. Tried in order; unknown files are skipped.
      ## Same-direction scripts only: mixed-direction text (e.g.
      ## Hebrew + Latin) needs a single covering font instead, since
      ## fallback runs shape in logical order.
    titleFaceIndex*: int
    bodyFaceIndex*: int

  OgError* = object of CatchableError

proc footerItem*(label: string, iconDark = "",
    iconLight = ""): OgFooterItem =
  ## One footer row item: `label` with an optional icon. The dark
  ## preset draws `iconDark`, the light preset `iconLight` (falling
  ## back to `iconDark`).
  OgFooterItem(iconDark: iconDark, iconLight: iconLight,
    label: label)

proc bgPosCenter*(): OgBgPos =
  ## Centered on both axes (`center center`).
  OgBgPos(centered: true)

proc bgPosPx*(x, y: float64): OgBgPos =
  ## Explicit top-left origin in user units (`px px`).
  OgBgPos(centered: false, x: x, y: y)

proc solidBackground*(c: Color): OgBackground =
  OgBackground(kind: bgSolid, color: c)

proc gradientBackground*(fromColor, toColor: Color,
    angleDeg = 135.0): OgBackground =
  OgBackground(kind: bgGradient, fromColor: fromColor, toColor: toColor,
    angleDeg: angleDeg)

proc imageBackground*(path: string, overlayAlpha = 0.55,
    tint = rgbf(0, 0, 0)): OgBackground =
  ## Cover-fit, centered, with a vertical scrim gradient (`#000`
  ## at `overlayAlpha` at the bottom fading to transparent) between
  ## the photo and the text. For full control use `imageBackgroundEx`.
  OgBackground(kind: bgImage, path: path, tint: tint,
    overlayAlpha: overlayAlpha, overlayAngleDeg: -90.0, fit: bgCover,
    pos: bgPosCenter())

proc imageBackgroundEx*(path: string, fit = bgCover,
    pos = bgPosCenter(), overlayAlpha = 0.55,
    tint = rgbf(0, 0, 0), overlayAngleDeg = -90.0): OgBackground =
  ## Full background-image control: `fit` selects cover (fill +
  ## crop), contain (fit inside + letterbox), or fill (stretch);
  ## `pos` is `bgPosCenter()` or `bgPosPx(x, y)`; the scrim runs
  ## from `tint` at `overlayAlpha` to transparent along
  ## `overlayAngleDeg` (-90.0 = opaque bottom, transparent top).
  OgBackground(kind: bgImage, path: path, tint: tint,
    overlayAlpha: overlayAlpha, overlayAngleDeg: overlayAngleDeg,
    fit: fit, pos: pos)

proc newOgImage*(title, description: string,
    preset = opDark): OgImage =
  ## Minimal constructor with standard 1200x630 dimensions.
  OgImage(width: 1200, height: 630,
    content: OgContent(title: title, description: description),
    preset: preset, accent: rgbf(0, 0, 0), hasAccent: false,
    hasBackground: false, titleFaceIndex: 0, bodyFaceIndex: 0)

proc newOgImage*(titleSegs, descSegs: seq[OgSeg],
    preset = opDark): OgImage =
  ## Segment constructor: rich title/description runs built with
  ## the `plain`/`strong`/`em`/`fg`/`bg`/`link` builders.
  OgImage(width: 1200, height: 630,
    content: OgContent(titleSegs: titleSegs, descSegs: descSegs),
    preset: preset, accent: rgbf(0, 0, 0), hasAccent: false,
    hasBackground: false, titleFaceIndex: 0, bodyFaceIndex: 0)
