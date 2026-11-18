<p align="center">
  Pure-Nim OpenGraph image generator (1200x630 PNG cards, zero native deps)<br>
</p>

<p align="center">
  <code>nimble install ogimage</code>
</p>

<p align="center">
  <a href="https://nimbase.github.io/ogimage/">API reference</a><br>
  <img src="https://github.com/nimbase/ogimage/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/nimbase/ogimage/workflows/docs/badge.svg" alt="Github Actions">
</p>


## Features
- Nim objects in, PNG out: build an `OgImage` value, call `savePng` or `encodePng`
- Six named presets: dark, light, gradient, photo, minimal, brand
- Background overrides: solid color, gradient, or image with cover/contain/fill and center (`bgPosCenter`) or px (`bgPosPx`) position, plus a `#000` to transparent scrim between bg image and text
- Segment rich text: `plain`/`strong`/`em`/`fg`/`bg`/`link` builders over nvg spans (no markup), with per-run faces, highlight boxes, and link styling
- Fixed type sizes with ellipsis trimming (long copy ends in `...`, never overflows)
- Photo avatar in the headline row (128x128, 20px rounded mask, cover-fit)
- Generic footer stats: icon + label items (handles, counters, captions) in one NVG flex row, auto dark/light icon variant
- Custom layouts: `layout` rows/columns compute absolute boxes, `newCustomCanvas` opens a blank canvas, and `drawBackground`/spans/`ellipsizeToLines` stay reusable — see `examples/custom.nim`
- Labeled gray placeholders (`128x128`, ...) wherever an image fails to load
- Retina output via `scale = 2.0` (2400x1260, same layout, same code)
- Cyrillic, RTL Hebrew (with right alignment), and fallback fonts
- Pure Nim on top of `nvg`: PNG encode included, no browser, no C libs

## Examples
```nim
import ogimage

var og = newOgImage("Pure-Nim OpenGraph images in one call",
  "Fixed sizes, ellipsis trimming, and named presets.",
  opDark)
og.content.badge = "nimbase"
og.content.footer = @[footerItem("@nimbase/ogimage",
  "tests/data/github-white.png", "tests/data/github-black.png"),
  footerItem("MIT")]
og.fontTitlePath = "tests/data/Roboto-Bold.ttf"
og.fontBodyPath = "tests/data/Roboto-Regular.ttf"
og.savePng("og_dark.png")

# Retina, photo avatar, RTL Hebrew (needs a Hebrew-covering font):
var og2 = newOgImage("תמונות OpenGraph ב־Nim טהור",
  "גדלים קבועים, חיתוך עם שלוש נקודות וערכות מוכנות.",
  opGradient)
og2.hasAlign = true
og2.align = thaRight
og2.fontTitlePath = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
og2.fontBodyPath = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
og2.scale = 2.0
og2.savePng("og_hebrew.png")

# Background image with fit + position (cover/contain/fill, center or px):
var og3 = newOgImage("Pure-Nim OpenGraph images in one call",
  "Fixed sizes, ellipsis trimming, and named presets.",
  opDark)
og3.hasBackground = true
og3.background = imageBackgroundEx(
  "tests/data/pexels-marie-gaebel-2164524425-40393792.jpeg",
  bgContain, bgPosCenter())
og3.savePng("og_bg_contain.png")

# Segment rich text, no markup (strong/em/fg/bg/link compose):
var og4 = newOgImage(
  @[plain("Ship "), strong(fg("faster", rgb(56, 189, 248)))],
  @[plain("Fixed sizes, "), em(plain("ellipsis trimming")),
    plain(" with "),
    bg(fg(plain("zero native deps"), rgb(15, 23, 42)),
      rgb(253, 224, 71))],
  opDark)
og4.fontEmPath = "tests/data/Roboto-Italic.ttf"
og4.savePng("og_rich.png")
```

| dark | photo |
| ---- | ----- |
| ![dark](examples/out/og_dark.png) | ![photo](examples/out/og_photo.png) |

| russian | hebrew |
| ------- | ------ |
| ![russian](examples/out/og_russian.png) | ![hebrew](examples/out/og_hebrew.png) |

| bg cover | rich |
| -------- | ---- |
| ![bg cover](examples/out/og_bg_cover.png) | ![rich](examples/out/og_rich.png) |

More cards (light, gradient, minimal, brand, long-copy ellipsis, missing-asset
placeholders, retina, background cover/contain/fill/position/gradient) are rendered by
`examples/demo.nim` into `examples/out/`. A custom split-hero layout (text column +
full-height image panel on a raw canvas) is rendered by `examples/custom.nim`
into `examples/out/og_custom.png`:

| custom |
| ------ |
| ![custom](examples/out/og_custom.png) |

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/nimbase/ogimage/issues)
- 👋 Wanna help? [Fork it!](https://github.com/nimbase/ogimage/fork)

### 🎩 License
MIT license | Nim Community.
