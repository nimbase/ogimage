## OpenGraph image generator in pure Nim on top of `nvg`.
##
## Build an `OgImage` value, pick a preset, render to PNG:
##
## ```nim
## import ogimage
##
## var og = newOgImage("Hello", "World", opDark)
## og.content.site = "example.com"
## og.savePng("og.png")
## ```

import ./ogimage/types
import ./ogimage/spans
import ./ogimage/layout
import ./ogimage/theme
import ./ogimage/fonts
import ./ogimage/render

export types
export spans
export layout
export theme
export fonts
export render
