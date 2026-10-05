extends RefCounted

## Every number the shell draws with, in one place.
##
## Not an autoload: nothing here has state or needs a node. Call sites do
## `const TvTheme = preload("res://src/tv_theme.gd")` and read the constants off
## the class. That keeps it greppable and keeps the values out of the scene tree.

const Icons = preload("res://src/icons.gd")
##
## ---------------------------------------------------------------------------
## Why these particular numbers
##
## The design surface is a fixed 1920x1080, scaled to the negotiated output by
## the project's canvas_items stretch. So every constant below is "at 1080p" and
## stays proportionally correct on a 4K panel.
##
## TV-safe inset: 5% of each edge, which the three platform vendors agree on and
## express identically -- Microsoft's 10-foot guidance and Android TV both work
## from a 960x540 surface with 48/27 margins, which is 96 px horizontal and 54 px
## vertical at 1080p; tvOS says 90/60. 5% is a floor, not a guarantee: individual
## TVs overscan more, and M2's camera test is the arbiter here the same way it is
## for the silent boot. If the TV clips, raise SAFE_MARGIN_* -- that is the one
## knob, and it is why the margins are constants rather than inline numbers.
##
## Type: Microsoft's floors are 15 epx for reading content and 12 epx for
## supplemental, against a surface Xbox scales 200% for TV -- 30 px and 24 px at
## 1080p. Nothing here goes below those, and project.godot raises Godot's default
## font size to 30 so a control that forgets to set one renders too big rather
## than invisibly small.
##
## Interactive elements are at least 32 epx / 64 px tall. A card is far above it.
##
## Colour stays inside RGB 16-235. TVs band and bloom at the extremes of the
## range, and the plan's risk table already treats TV colour behaviour as
## untrusted. Nothing here is pure black or pure white.

const BASE_WIDTH := 1920
const BASE_HEIGHT := 1080

# 5% of each axis. See the header: this is the knob the camera test turns.
const SAFE_MARGIN_X := 96
const SAFE_MARGIN_Y := 54

# ---------------------------------------------------------------------------
# The console-style home rail
#
# A horizontal row of cards with one enlarged selection, rather than a grid. The
# difference is not decoration: a rail has ONE axis, so left and right are the
# only moves that mean anything and there is no ambiguity about where focus goes
# next -- which is the property that makes a games console readable from a sofa
# with a thumbstick. The grid's 2D neighbour table exists to paper over exactly
# that ambiguity.
#
# The selected card sits at a FIXED x on screen and the rail slides underneath
# it. Anchoring the selection rather than the strip is what stops the eye having
# to re-find the cursor after every press.

## Unfocused card. Square, because a square is the only aspect ratio that reads
## the same whether the art is portrait key art or a square icon, and Phase 1
## does not get to choose what AppStream hands it.
const CARD_SIZE := 200

## The selected card. Roughly 1.7x, which is the point where the size difference
## is legible at three metres rather than merely present -- the same argument as
## FOCUS_RING_WIDTH being a floor to multiply rather than a value to copy.
const CARD_FOCUSED_SIZE := 340

const CARD_GAP := 26

## THE ROUNDING, and it was 12 until someone looked at the appliance on a TV and
## said the buttons were not rounded. They were -- by 12 px on a 1920-wide design
## surface, which is a chamfer you can measure and cannot see from a sofa. Every
## focusable rectangle in the shell reads its corner radius from here (cards,
## settings rows, store tabs, the app menu's panel), so one number is the whole
## of how round this product looks, and it is deliberately not per-control.
##
## 24 rather than a pill. The rows are SETTINGS_ROW_HEIGHT tall, so half their
## height would be 44 and would turn a list of rows into a stack of lozenges;
## 24 is unmistakably round at three metres while a row still reads as a row.
const CARD_CORNER_RADIUS := 24

## Inset from a card's edge to its icon, at CARD_SIZE. An app icon sits inside
## the card's wash the way a launcher tile's does -- roughly two thirds of the
## card, so the wash reads as a frame rather than a border. A fixed pixel inset
## means the icon grows with the card when it takes focus, which is what keeps
## the selection's size channel working.
const CARD_ICON_INSET := 34

## How long the rail takes to slide and the card to grow. Long enough to read as
## motion, short enough that holding a direction does not feel like wading --
## FocusRepeat's hold-repeat interval is the real ceiling on this.
const RAIL_TWEEN_SECONDS := 0.18

## The accent wash's strength -- the BASE layer of the home background now,
## and the whole background only for an entry that ships no picture (the
## HERO_ART_* block below is what draws over it when there is one). At full
## strength the wash would make white text illegible; the number keeps
## TEXT_PRIMARY above 4.5:1 against the brightest accent in the catalogue.
const HERO_DIM := 0.22

## Height of the gradient that darkens the lower half, as a fraction of the
## surface. Text sits inside it; the wash is only visible above.
const HERO_GRADIENT_FRACTION := 0.62

# ---------------------------------------------------------------------------
# The hero ART -- the selected entry's own picture as the WHOLE background
#
# Playnite and the PS5 both do the same thing and it is the reason either
# screen feels like a library rather than a menu: moving the selection repaints
# the entire surface, not a strip of it. The accent wash above stays as the base
# layer and as the whole answer for an entry with no picture, because roughly
# half a real rail (built-in surfaces, apps whose flatpak exports nothing) has
# none.
#
# Everything below is chosen against llvmpipe, which is the renderer this
# appliance actually has: no shader, no per-frame filter, nothing that costs
# anything once the frame has settled.

## How long after the selection settles before the picture is loaded.
##
## THE POINT IS THE HOLD. Leaning right across ten cards fires ten selections
## in about a second, and without this each one would decode a JPEG and start a
## fade -- ten loads and ten tweens for a rail nobody was looking at on the way
## past. The timer is restarted by every selection, so only the card the thumb
## comes to rest on pays. Deliberately shorter than the eye needs to read a card
## (~0.25 s), so a deliberate single press still feels like it answered at once.
const HERO_ART_DEBOUNCE_SECONDS := 0.15

## The crossfade between the outgoing picture and the incoming one. A shade
## longer than RAIL_TWEEN_SECONDS: the rail's slide is a small object moving and
## reads as fast, while a full-screen image changing in the same time reads as a
## flash.
const HERO_ART_FADE_SECONDS := 0.22

## The flat scrim over the picture, as an alpha of BACKGROUND.
##
## NOT A TASTE SETTING -- it is worked backwards from the worst art the machine
## can be handed, which is a Steam portrait that is mostly white. At 0.70, white
## art lands at ~0.36 luminance, and under the bottom gradient where the
## SUBTITLE sits (~0.36 alpha there) that becomes ~0.26, which puts
## TEXT_SECONDARY at ~3.4:1 and TEXT_PRIMARY at ~7:1. Drop the scrim to 0.55 and
## the subtitle falls to ~2.4:1 -- unreadable over a white box shot, which is
## exactly the case that has to work. What is left of the art at 30% is still
## unmistakably a picture, which is all a backdrop is for.
##
## ONE VALUE, AND THE SHARP HERO DOES NOT GET ITS OWN. A game's hero background
## is now drawn unsoftened (shell_root._backdrop_texture), which is a real change
## to what is behind the text -- so the number was re-derived rather than assumed
## to carry. It carries, because the derivation above is about LUMINANCE and
## nothing else: 0.70 is worked from the brightest pixel the machine can be
## handed, and a white pixel is a white pixel whether it arrived sharp or as a
## 50 px smear blown up. Resizing an image cannot make it brighter than its
## brightest region, so a sharp hero's worst case is the case already solved, and
## a hero-specific constant would be a second number to keep in step with the
## same argument. What sharpness adds is DETAIL behind the text, not luminance --
## and the bottom gradient (0.96 at the baseline, where the title and subtitle
## sit) is the layer that answers that, unchanged and already stronger than the
## flat scrim over it. Steam's own library draws these images edge to edge with
## far less protection than this.
const HERO_ART_SCRIM := 0.70

## A second gradient, at the TOP, only over the picture.
##
## The bottom gradient protects the title, the subtitle and the rail. Nothing
## protected the top bar, because until there was art up there it had only the
## dimmed wash under it -- and the wordmark, the clock and the controller line
## over bright art were the one place the flat scrim alone did not carry.
const HERO_ART_TOP_FRACTION := 0.26
const HERO_ART_TOP_ALPHA := 0.88

## THE BLUR, AND THERE IS NO BLUR. A picture at full sharpness behind text is
## visual noise, and every real way to soften one -- a shader, a per-frame
## filter, a repeated texture read -- is a per-frame cost on a machine whose
## renderer is a CPU. So the image is resized DOWN to a handful of pixels once,
## when the selection settles, and the linear filtering that would upscale any
## texture smears it back across the screen for free. The cost is one CPU
## resize per picture per boot; the per-frame cost is exactly that of drawing
## any other texture.
##
## A 600x900 Steam portrait divided by 12 is 50x75 -- still recognisably the box
## art, just soft. A SQUARE LOGO GETS TWICE THE TREATMENT, and the result is not
## a mistake: a 256 px flatpak icon at 1/24 is a 10 px smear blown up to fill a
## 2580 px ultrawide, which is abstract colour rather than a picture of
## anything. That is the intended look and it is what Playnite does with
## icon-only entries -- the card already shows the logo sharply, and the
## background's job is to be the entry's colour, at the scale of a wall.
const HERO_ART_BLUR_DIVISOR := 12
const HERO_ART_BLUR_DIVISOR_SQUARE := 24
const HERO_ART_BLUR_MIN := 8

## How far from 1:1 an image may be and still count as a logo rather than key
## art. Wide enough to catch icons that are a pixel or two off square, narrow
## enough that a 600x900 portrait (0.67) is nowhere near it.
const HERO_ART_SQUARE_TOLERANCE := 0.2

## How many decoded backdrops are kept. The set is a rail's worth -- a dozen or
## two cards, each a few kilobytes once resized -- so this is a cap against a
## pathological rail rather than a working eviction policy anyone will hit.
const HERO_ART_CACHE_MAX := 16

const SIZE_HERO_TITLE := 72
const SIZE_TOPBAR := 28

# ---------------------------------------------------------------------------
# The top bar's icon buttons (PS5-shaped: store and settings live in the bar)
#
# The bar stopped being pure text when the settings entry moved off the rail at
# the owner's request (ADR 0006, third amendment): store and settings are now
# focusable icons on the right of the bar, PS5-fashion, and the rail gained a
# second axis -- up from any card lands on the store icon. The icons are drawn
# with primitives in glyphs.gd rather than shipped as textures: an icon font or
# a PNG would be the repo's first binary asset, and three glyphs' worth of arcs
# and rectangles is reviewable the way every other number here is.

## Exactly the interactive floor from the header. The glyph inside is smaller;
## the box is the focus target and the thing the ring draws around.
const TOPBAR_ICON_SIZE := 64

## Inset from the icon box's edge to the glyph's drawing area. Chosen so the
## glyph reads at three metres without the box crowding it.
const TOPBAR_ICON_PAD := 14

## Line weight for glyph strokes. Matches the focus ring's weight so the two
## read as one family of marks.
const TOPBAR_GLYPH_WIDTH := 4.0

# ---------------------------------------------------------------------------
# The stores screen
#
# Side tabs on the left, the selected store's page rendered on the right --
# the PS Store shape. The page is drawn BY THE SHELL (title, art wash,
# description, live install state); pressing A launches the store application
# itself fullscreen, because embedding a foreign client's window inside a
# Godot control is compositor work this stack does not do. See ADR 0006's
# third amendment.

## Side of a store tab, which is square and carries only the store's icon (see
## store_tab.gd). This was STORE_TAB_WIDTH := 420, sized to hold a store NAME at
## SIZE_BODY; with the name gone the column is a strip of marks, and the width it
## no longer needs goes to the page beside it. Comfortably above the interactive
## floor in this file's header.
const STORE_TAB_SIZE := 132

## The stand-in glyph inside a tab, for a store whose application is not
## installed yet. Sized against STORE_TAB_SIZE rather than against the body
## text: it is the tab's whole content, not a mark beside a word.
const STORE_TAB_GLYPH_SIZE := 64

## Breathing room between a tab's edge and the real application icon it draws.
## Larger than the glyph needs because a PNG icon fills its square to the corners
## while a Phosphor mark carries its own margin.
const STORE_TAB_ICON_INSET := 22

## Gap between the tab column and the page pane.
const STORE_PAGE_GAP := 40

## Padding inside the page pane, between its rounded edge and its content.
const STORE_PAGE_PAD := 48

## Height of the accent wash band at the top of a store page -- stands in for
## key art the same way the rail's hero wash does. Drawn on a page that is
## DESCRIBING a store; the storefront grid below replaces it with real capsules
## the moment there is a storefront to draw.
const STORE_PAGE_HERO_HEIGHT := 220

# ---------------------------------------------------------------------------
# The file manager
#
# Dolphin's shape, at TV scale and on a pad: a Places column on the left that
# never goes away, one or two view panes beside it, and a view that can be
# icons, compact or details. The numbers here are what make that layout land
# inside the safe area at 1080p and stay legible at three metres -- which is
# the whole reason this is a redraw of Dolphin rather than Dolphin.

## The Places column. Wide enough for the longest name plus a free-space figure
## on one line at SIZE_BODY -- "Home  737.5 GB free" is the case that sets it,
## and it was 340 until a screenshot showed every value on the column rendering
## as "737.5 G...". Narrow enough that a split view still gets two panes of real
## width out of the remaining ~1100 px at the design size.
const FILES_PLACES_WIDTH := 420

## Between the Places column and the panes, and between the two panes. Larger
## than SETTINGS_ROW_GAP because these are separate REGIONS of focus, not rows
## in one list -- the gap is what says "left again leaves this pane".
const FILES_PANE_GAP := 24

## Padding inside a pane's frame, between its rounded edge and its content.
const FILES_PANE_PAD := 20

## A details row: name, size, date. Shorter than SETTINGS_ROW_HEIGHT's 88
## because a file list is long and a settings list is not -- 72 fits fourteen
## rows in the safe height where 88 fits eleven, and it is still comfortably
## above the 64 px interactive floor in this file's header.
const FILES_DETAILS_HEIGHT := 72

## An icon-view cell. Square-ish: a thumbnail above, one or two lines of name
## below. This is Dolphin's Icons mode, and the size is set by the thumbnail
## being readable as a PICTURE from a sofa rather than by fitting a target
## number of columns.
const FILES_ICON_CELL := 210
const FILES_ICON_CELL_HEIGHT := 240

## Compact mode: Dolphin's third view -- name only, in narrow columns. The
## height is exactly the interactive floor, because the whole point of the mode
## is fitting the most rows on screen.
const FILES_COMPACT_WIDTH := 340
const FILES_COMPACT_HEIGHT := 64

## The thumbnail inside an icon cell, and the glyph that stands in for a file
## with no picture to show.
const FILES_THUMB_SIZE := 132
const FILES_ROW_GLYPH_SIZE := 34

## THE DECODE CAP. A thumbnail is drawn at FILES_THUMB_SIZE, so nothing is
## gained by keeping a 6000 px camera JPEG in memory at full size -- and a
## directory of forty of them would be gigabytes. Every thumbnail is resized to
## this on the long edge immediately after decode and the source image dropped.
const FILES_THUMB_DECODE := 256

## How many decoded thumbnails are kept, across every directory visited while
## the screen is open. A directory of photos is the case this exists for;
## sixty-four at 256 px is a few megabytes, and the eviction is oldest-first so
## walking a big folder cannot grow without bound.
const FILES_THUMB_CACHE_MAX := 64

## How many thumbnails are decoded per frame while a directory is being
## rendered. THE POINT IS THE CEILING, not the number: this machine's renderer
## is llvmpipe and its decoder is one CPU thread, so a folder of eighty photos
## decoded in one frame is a shell that stops answering the pad for several
## seconds. Spreading the work leaves the list navigable while the pictures
## fill in behind it, which is what every file manager does.
const FILES_THUMBS_PER_FRAME := 2

# The storefront grid -- Steam's own front page, drawn by this shell
#
# The numbers here are worked back from the pane the grid has to live in, which
# is the one place in this file where that is true of a whole block rather than
# of one constant. At 1080p the safe area is 1728 wide; the tab column takes
# STORE_TAB_SIZE and STORE_PAGE_GAP, and the pane's own STORE_PAGE_PAD takes 48
# from each side, which leaves about 1460 px of shelf. Four columns of
# STORE_ITEM_WIDTH with STORE_GRID_GAP between them is 1420 -- a column short
# of the edge, deliberately, so the focus ring never grazes the pane's rounded
# corner.
#
# On the ultrawide the design surface is ~2580 wide and the pane simply gets
# roomier; the grid stays four columns rather than growing, because a fifth
# column at this tile size would put the last capsule further from the eye than
# a thumb wants to travel and because the shelf is browsed by moving, not by
# seeing everything at once.

## A shelf tile. The art is Valve's 616x353 capsule, so the tile's picture is
## that aspect exactly -- STORE_ITEM_ART_HEIGHT is STORE_ITEM_WIDTH divided by
## 1.745 and rounded. Getting this wrong is not a layout nit: a capsule
## letterboxed into the wrong box is a black band across every tile on the
## screen.
const STORE_ITEM_WIDTH := 340
## THE HEIGHT IS A SUM, NOT A GUESS, and it has to be: a tile's contents are
## anchored children of a Button, and a Button's minimum size ignores its
## children entirely -- so a tile too short does not grow, it spills, and the
## first render of this grid had every discount line hanging below its own
## focus ring and into the shelf underneath. The sum is the picture (190), three
## text lines at their line heights (~35 + ~35 + ~33), the separations between
## them (3 x 6) and STORE_ITEM_PAD top and bottom: 335, rounded up to 340.
## Anything added to a tile has to be added here too.
const STORE_ITEM_HEIGHT := 340
const STORE_ITEM_ART_HEIGHT := 190

## The struck-price line's type size. Smaller than the name and the price
## because it is the least important of the three, and NOT smaller than 24 --
## which is this file's supplemental floor from the header (Microsoft's 12 epx
## against a surface Xbox scales 200% for TV), and the reason this is a named
## constant rather than an arithmetic expression on SIZE_SUPPLEMENTAL that
## could quietly slide under it.
const STORE_ITEM_WAS_SIZE := 24

## Inside a tile: between its rounded edge and the picture, and between the
## picture and the name below it.
const STORE_ITEM_PAD := 12

const STORE_GRID_COLUMNS := 4
const STORE_GRID_GAP := 20

## Between one shelf's heading and the grid under it, and between shelves.
const STORE_SHELF_GAP := 18

## The detail sub-view's picture. Most of the pane's width at a screenshot's
## 16:9, which is why it is well over the tile's -- the whole reason the service
## fetches a full screenshot rather than reusing the capsule.
##
## 300 AND NOT 360, AND THE NUMBER IS ARITHMETIC RATHER THAN TASTE. The page
## grew a second action row when Play/Install landed, and the pane has a fixed
## height: 972 of design surface less the heading, the hint row and their
## SECTION_GAPs is about 796, less STORE_PAGE_PAD top and bottom is 700. The
## children below the picture come to 322 (title 70, prices 38, summary 38, two
## SETTINGS_ROW_HEIGHT rows at 88) plus 60 of STORE_ITEM_PAD separation, so the
## picture may have 318 at the very most. At 360 the second row was drawn past
## the bottom edge of the pane -- visible in a harness screenshot on 2026-08-11,
## and invisible to every assertion in this project, because a Godot Control
## laid out past its parent is not an error anywhere. It is the one defect class
## the invisible harness catches that the journal never will.
const STORE_DETAIL_ART_HEIGHT := 300

## The sign-in QR, drawn square because a QR is one. Sized against the same
## budget as the detail art above -- it lives in the same pane -- and against
## what the picture is FOR: a phone camera across a living room wants modules
## it can resolve, and marwanos-steamfront renders them eight pixels each, so
## ~300 is close to the PNG's native size and the nearest-neighbour scale
## stays crisp. Smaller would blur modules together; the camera loses before
## the eye does.
const STORE_QR_SIZE := 300

# ---------------------------------------------------------------------------
# The Steam library shelf
#
# The storefront's grid above is DELETED CODE'S NEIGHBOUR: its numbers survive
# because the constants are still referenced, but the shelf this block sizes is
# a different object drawn from a different picture. ADR 0010 replaced a shop
# with a library, and a library's tile is a game somebody already owns.
#
# THE ASPECT IS THE WHOLE REASON THIS IS NOT STORE_ITEM_*. A storefront tile
# drew Valve's 616x353 capsule and was 1.745 times wider than tall; the client
# contract says a library picture is library_600x900, which is PORTRAIT at 2:3
# -- so reusing the capsule's box would letterbox every game on the screen
# inside two black pillars. The art height is the width times 1.5, exactly.

## One game. Narrower than a storefront tile because there are hundreds of them
## rather than a curated eight, and because portrait art at this width still
## shows a title a person recognises from three metres -- which is the only job
## the picture has.
##
## 260 RATHER THAN 220, AND A SCREENSHOT IS WHY. At 220 the state line under a
## downloading game rendered as "Downloading 4..." -- the ellipsis ate the
## percentage, which is the single number somebody watching a download is
## looking at. Measured against a fixture shelf on 2026-08-12, not reasoned
## about: the label is set to trim with an ellipsis rather than wrap, so a
## string one glyph too long loses its most important glyphs silently and the
## layout looks perfectly healthy while doing it.
##
## The fix is the box rather than the sentence because shortening the sentence
## only moves the cliff: "Downloading 100%" is wider than "Downloading 42%", so
## a tile cut to fit the common case truncates exactly as the download finishes.
const STEAM_TILE_WIDTH := 260
const STEAM_TILE_ART_HEIGHT := 390

## THE HEIGHT IS A SUM, NOT A GUESS, for STORE_ITEM_HEIGHT's reason and the same
## Godot rule behind it: a tile's contents are anchored children of a Button, a
## Button's minimum size ignores its children entirely, and a tile too short does
## not grow -- it spills into the row underneath. The sum is the picture (330),
## the name and the state line at their line heights (~35 + ~33), the two
## separations between the three (2 x 6) and STORE_ITEM_PAD top and bottom: 494,
## rounded up. Anything added to a tile has to be added here too.
const STEAM_TILE_HEIGHT := 500

## Five columns, following the tile from 220 to 260. At 1080p the safe area is
## 1728 wide and the pane's padding takes 48 from each side, leaving ~1632: five
## tiles and four STORE_GRID_GAPs is 1396, which leaves the focus ring clear of
## the pane's rounded corner. Six would be 1680 and would not fit. The count
## stays five on the ultrawide rather than growing, for the storefront's
## argument: a shelf is browsed by moving, not by seeing all of it at once.
const STEAM_GRID_COLUMNS := 5

## A discount, and the one place in this file where a hue carries meaning. It
## is deliberately NOT the only channel: the tile says "was $59.99 (-70%)" in
## words underneath, so the colour is emphasis on a fact already stated rather
## than the fact itself -- which is the same rule the focus indicator follows
## three constants down. Inside RGB 16-235 and ~7:1 against SURFACE.
const TEXT_DISCOUNT := Color(0.529412, 0.780392, 0.423529, 1.0)

# The focus indicator runs on three channels at once, because colour alone is
# unreliable on a TV and because WCAG 2.2 SC 2.4.13 asks for a >= 3:1 contrast
# between the focused and unfocused states of the same pixels -- a state-change
# ratio, which one channel struggles to carry. The channels are: a ring
# (FOCUS_RING vs the card beneath it is ~8:1), a brighter surface, and size --
# the card growing from CARD_SIZE to CARD_FOCUSED_SIZE.
#
# WCAG's 2-CSS-px thickness figure is calibrated for a monitor at desk distance
# and is invisible from a sofa. Take the contrast requirement as binding and the
# thickness as a floor to multiply.
const FOCUS_RING_WIDTH := 6

const SIZE_WORDMARK := 56
const SIZE_BODY := 30
const SIZE_SUPPLEMENTAL := 26

## Vertical breathing room between the top bar, the title block, the rail and
## the hint row.
const SECTION_GAP := 28

# ---------------------------------------------------------------------------
# The details panel (DOWN from a card on the home rail)
#
# A sheet that slides up over the LOWER PART of the home screen: the entry's
# title, what the thing actually is, and one button that starts it. The top of
# the surface is deliberately left alone, because what is up there is the game's
# own background -- a panel that covered the whole screen would hide the picture
# the person pressed down to find out about.

## How tall the sheet is, against the 1080 design height.
##
## IT IS THE TITLE BLOCK THAT SETS THIS, not a fraction anyone liked the look of.
## The home screen's rows are laid out from the bottom -- hints, rail, title,
## with the slack pushed above them (shell_root._build) -- which puts the hero
## title and its subtitle at roughly y 450 to 585 on the design surface. The
## sheet restates the title, so it has to cover that block completely: 600 was
## the first value tried and its top edge landed at 480, slicing the hero title
## in half lengthwise, which on the Xvfb screenshot read as a rendering fault
## rather than as a panel. 720 puts the top edge at 360, clear of the block by
## enough that no future retune of SECTION_GAP re-opens the defect -- and still
## leaves a third of the surface showing the picture, which is the whole reason
## this is a sheet rather than a screen.
const DETAILS_PANEL_HEIGHT := 720

## How long the sheet takes to arrive. Longer than RAIL_TWEEN_SECONDS because it
## is a large object travelling a long way -- the rail's slide is a card moving a
## card's width -- and shorter than the eye spends reading the first word of the
## title, so nothing is ever waited for.
const DETAILS_SLIDE_SECONDS := 0.24

## The Play button's width. A settings row expands to fill its column, which is
## right for a list of rows and wrong for one button sitting under a paragraph:
## full-width, it reads as another band of the panel rather than as the thing to
## press. Comfortably wide enough for a word and a focus ring at three metres.
const DETAILS_BUTTON_WIDTH := 420

# ---------------------------------------------------------------------------
# The settings screen
#
# Rows reuse the card's boxes and ring so the two screens read as one product.
# A row's focus runs on two channels (the ring and the brighter surface) where
# the card's runs on three, because the third does not transfer: a card grows
# into slack the rail keeps around it, but a full-width row that grew would
# shove every row below it, and a list that reflows on each press reads as
# nervous. The ring's ~8:1 against the surface carries WCAG's state-change
# contrast on its own, so dropping size costs redundancy, not legibility.

## Comfortably above the 64 px interactive floor named in the header, and tall
## enough that a name on the left and a value on the right read as one line
## from the couch.
const SETTINGS_ROW_HEIGHT := 88

const SETTINGS_ROW_GAP := 14

## Horizontal padding inside a row, between its rounded edge and its text.
const SETTINGS_ROW_PAD := 28

## (The settings card's accent lived here until the third amendment moved
## settings into the top bar as a gear icon; the constant went with the card.)

# RGB 16-235, light-on-dark, no hue carrying meaning on its own.
const BACKGROUND := Color(0.078431, 0.086275, 0.101961, 1.0)
const SURFACE := Color(0.149020, 0.164706, 0.196078, 1.0)
const SURFACE_FOCUS := Color(0.290196, 0.321569, 0.376471, 1.0)
## One step brighter than SURFACE_FOCUS, for the moment a press is held on a
## row that has no scene change to acknowledge it -- see settings_row.gd.
const SURFACE_PRESSED := Color(0.380392, 0.419608, 0.490196, 1.0)
## A SELECTED item, which is a state the shell had no need for until the file
## manager grew multi-select. It is deliberately a HUE change rather than
## another step on the same grey ramp: an item can be selected and unfocused,
## focused and unselected, or both, and three points on one brightness ramp
## cannot be told apart at three metres. Selection is also carried by a check
## mark on the item itself (see file_item.gd) -- colour alone is unreliable on
## a TV, which is the same argument the focus ring's three channels rest on.
const SURFACE_SELECTED := Color(0.152941, 0.250980, 0.372549, 1.0)
const SURFACE_SELECTED_FOCUS := Color(0.250980, 0.396078, 0.549020, 1.0)

## The frame around the pane that has focus, in a split view. Nothing else on
## screen tells you which side a paste would land in, and "the one with the
## focus ring in it" is not readable when the ring is on a row halfway down a
## list you are not looking at.
const PANE_ACTIVE_BORDER := Color(0.435294, 0.529412, 0.639216, 1.0)
const PANE_BORDER_WIDTH := 3

const FOCUS_RING := Color(0.909804, 0.917647, 0.933333, 1.0)
const TEXT_PRIMARY := Color(0.886275, 0.901961, 0.921569, 1.0)
const TEXT_SECONDARY := Color(0.588235, 0.619608, 0.666667, 1.0)
const TEXT_ALERT := Color(0.921569, 0.690196, 0.360784, 1.0)
const ACCENT_FALLBACK := Color(0.290196, 0.321569, 0.376471, 1.0)

## The hint row's numbers, shared by every screen that draws one.
const HINT_GAP := 36
const HINT_GLYPH_GAP := 12


## The card's art fill, rounded to the same radius as the box and the ring.
##
## It is a StyleBoxFlat on a Panel rather than a ColorRect, and that is a fix
## rather than a preference: a ColorRect is always a hard rectangle, so its four
## square corners drew outside the rounded focus ring and the rounded card box
## beneath it. On hardware that reads as the art leaking past its own border --
## reported off the 2026-08-07 boot, and invisible until the ring started
## drawing at all. Phase 1 replaces the flat colour with real key art, which
## will need the same treatment (a texture rounded by a corner radius, not a
## bare TextureRect) for exactly this reason.
static func card_art_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## A rail card at rest. No border: on a rail the selection is carried by size and
## by the ring, and a border on every card competes with both.
static func card_idle_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## The selected card. Brighter surface plus the ring -- see the three-channel
## comment above FOCUS_RING_WIDTH.
static func card_focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_FOCUS
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## The focus ring. draw_center is off so it is purely an outline and the
## brightness channel stays independent of it. The card draws this on an overlay
## child above its full-bleed art, NOT as Button's "focus" stylebox -- a Button
## paints that box before its children, so the art would swallow it whole. See
## tile.gd's _build_contents.
##
## THE RADIUS IS AN ARGUMENT BECAUSE A CARD IS NO LONGER ALWAYS ROUNDED. A game
## whose own artwork fills its tile edge to edge draws no plate at all, and a
## rounded ring over square art is the leak card_art_box's comment above
## describes, arriving from the other side: the art's four corners sit OUTSIDE
## the ring's curve and poke past it. The default is unchanged, so every caller
## that has a rounded box under it stays exactly as it was; the chromeless card
## passes 0 and gets an outline that follows its picture.
static func card_focus_ring(radius: int = CARD_CORNER_RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(FOCUS_RING_WIDTH)
	box.border_color = FOCUS_RING
	box.set_corner_radius_all(radius)
	return box


## Top-to-bottom transparent-to-dark, so the title and rail keep their contrast
## over any hero wash. A GradientTexture2D rather than a shader: it is one
## resource, it costs nothing on llvmpipe, and it is reviewable as numbers.
static func hero_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.0))
	gradient.set_color(1, Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.96))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	# Small: it is stretched across the surface and the ramp is linear, so there
	# is nothing for more texels to describe.
	texture.width = 2
	texture.height = 256
	return texture


## The mirror of hero_gradient, at the top of the surface, drawn only where
## there is key art to darken. See HERO_ART_TOP_FRACTION for why the top bar
## needs its own band and the wash-only screen does not.
static func hero_top_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, HERO_ART_TOP_ALPHA))
	gradient.set_color(1, Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 2
	texture.height = 256
	return texture


## The flat scrim laid over key art, edge to edge. BACKGROUND rather than black,
## so a dimmed picture tends towards the colour the rest of the shell is made of
## rather than towards a hole in it. See HERO_ART_SCRIM for where the alpha
## comes from.
static func hero_scrim_color() -> Color:
	return Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, HERO_ART_SCRIM)


## A file-manager item's box, across the two states that can each be on or off.
## One function rather than four constants so the four combinations are decided
## in one place and cannot drift into "selected looks focused" -- which on a
## screen where a delete acts on the SELECTION and not on the cursor would be
## the most expensive possible confusion.
static func file_item_box(selected: bool, focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	if selected:
		box.bg_color = SURFACE_SELECTED_FOCUS if focused else SURFACE_SELECTED
	else:
		box.bg_color = SURFACE_FOCUS if focused else SURFACE
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## The frame around a view pane. Only the ACTIVE pane draws a coloured border;
## the other draws the same frame in the surface colour, so the two panes stay
## the same size and nothing reflows when focus crosses between them.
static func pane_frame(active: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BACKGROUND
	box.set_border_width_all(PANE_BORDER_WIDTH)
	box.border_color = PANE_ACTIVE_BORDER if active else SURFACE
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## The details sheet has NO surface. Pressing down on a game shows the game's own
## key art with the panel's words over it, and nothing between the two.
##
## IT WAS AN OPAQUE SLAB, and the slab was doing a second job nobody asked it to
## do: it was how the panel HID the home screen. The rail, the title block and
## the hint row are all still in the tree while the panel is up, and covering
## them with a rectangle is what stopped the panel's title drawing on top of the
## home screen's title. Taking the colour away exposes that -- so shell_root now
## hides those three explicitly while the panel is open, which is the honest
## version of what this colour was quietly doing. See _on_details_requested.
##
## LEGIBILITY IS NOT LEFT TO LUCK, and it is not this box's job either. The home
## screen already darkens the bottom of the surface behind the rail
## (HERO_GRADIENT_FRACTION), which is the band the sheet occupies, so the panel's
## text sits on the darkened part of the art rather than on raw key art.
##
## Returns StyleBoxEmpty, so the type widened to StyleBox. The old rounded-top
## comment went with the colour: a transparent box has no corners to round, and
## the "notch of background at the bottom edge" it was avoiding cannot happen to
## something that draws no pixels.
static func details_sheet_box() -> StyleBox:
	return StyleBoxEmpty.new()


## A row that is being pressed and has nothing else to say so. Brighter than
## the focus surface, so the press is a visible pixel change even though the
## row was already lit by focus when the button went down.
static func row_pressed_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_PRESSED
	box.set_corner_radius_all(CARD_CORNER_RADIUS)
	return box


## THE HINT BADGE IS A CIRCLE, and it was a rounded square until someone looked
## at the appliance on a TV. A pad's face buttons ARE circles -- moulded round on
## every controller in the room -- so a cross drawn inside a square box is the
## legend disagreeing with the hardware it is a legend for, which is exactly the
## kind of small wrongness that makes a hint row read as decoration rather than
## as instruction.
##
## The number is the badge's outside diameter, and it is the one knob: the box's
## corner radius is half of it (StyleBoxFlat clamps radii to the rect, so half
## the height is a true circle and never an over-rounded rectangle), and the
## badge Label is given the same value as a square minimum size. 46 rather than
## something snug around SIZE_SUPPLEMENTAL's 26, because a circle circumscribes
## the glyph where a square inscribed it -- a ring drawn tight to a 26 px mark
## clips its corners.
const HINT_BADGE_SIZE := 46


## The circle behind a button glyph in the hint row -- see HINT_BADGE_SIZE.
##
## `word` is the escape hatch for a badge that is text rather than a face-button
## mark ("OPTIONS", "Shift"): a circle cannot hold seven letters, so those get
## the same fully-rounded box stretched into a lozenge. Still round-ended, still
## not the square this replaced, and the two are one function so a retune of the
## border or the fill cannot land on only one of them.
static func glyph_box(word: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE
	box.set_border_width_all(2)
	box.border_color = TEXT_SECONDARY
	box.set_corner_radius_all(HINT_BADGE_SIZE / 2)
	if word:
		box.content_margin_left = 18
		box.content_margin_right = 18
	return box


## The pad's face buttons as the DualSense actually labels them. The hint row
## used to say "A" and "B" -- correct for the logical action, wrong for the
## pad in the room, whose buttons say nothing of the kind. The LETTERS remain
## the API (call sites say what Godot's input map says: A confirms, B cancels)
## and this table is the one place that knows A is drawn as a cross and B as a
## circle. An Xbox pad arriving would make this a per-pad lookup keyed on
## PlayerOne's identity; today there is one controller and it is a DualSense.
const HINT_SHAPES := {
	"A": "cross",
	"B": "circle",
	"X": "square",
	"Y": "triangle",
}


## THE ONE-AXIS FOCUS TABLE, which every vertical list in this shell was
## carrying its own byte-identical copy of.
##
## Up and down move, both ends are hard stops, and left and right are pointed at
## self so Control's geometric search cannot wander sideways out of the list --
## into the hint row, into the top bar behind a menu panel, into whatever else
## happens to be findable. Nine files had spelled that out identically (settings,
## info, the two menus that are now one, services, power, wifi, updates, places,
## the app overlay), each with its own paraphrase of the same comment, and the
## processes menu's copy -- service_menu.gd, as it was called then -- had got as
## far as calling itself "the settings list's table, a fourth time". One of the
## nine has since gone entirely: the quick settings panel hand-wrote the table
## rather than calling this, and the menu rewrite of 2026-08-12 deleted the
## panel.
##
## Rows that need a DIFFERENT table still write their own: places_panel has an
## argument about its right edge, keyboard is a grid, details_panel is one
## control that closes on up. Those are decisions, not copies, and this helper
## deliberately does not try to express them.
static func wire_column(rows: Array) -> void:
	var count := rows.size()
	for index in count:
		var row: Control = rows[index]
		var up := index - 1 if index > 0 else index
		var down := index + 1 if index + 1 < count else index
		row.focus_neighbor_top = row.get_path_to(rows[up])
		row.focus_neighbor_bottom = row.get_path_to(rows[down])
		row.focus_neighbor_left = row.get_path_to(row)
		row.focus_neighbor_right = row.get_path_to(row)


## One glyph-plus-caption hint, e.g. cross + "Open". Built here rather than in
## each screen because the settings screen made it the first duplicated control
## in the project, and a third fullscreen surface copying the pattern would
## have made it three sites to retune after a couch test.
static func hint(glyph: String, caption_text: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", HINT_GLYPH_GAP)

	var is_shape := HINT_SHAPES.has(glyph)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", SIZE_SUPPLEMENTAL)
	badge.add_theme_color_override("font_color", TEXT_PRIMARY)
	badge.add_theme_stylebox_override("normal", glyph_box(not is_shape))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A face-button badge is a CIRCLE, so its box has to be square -- a Label
	# sized by its own one glyph is taller than it is wide, and the rounded box
	# would come out as a vertical lozenge. A word badge only pins the height,
	# and its width follows the letters.
	badge.custom_minimum_size = Vector2(
		HINT_BADGE_SIZE if is_shape else 0, HINT_BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_shape:
		# A face button: draw the PS shape in the icon font.
		badge.add_theme_font_override("font", Icons.font())
		badge.text = Icons.glyph(str(HINT_SHAPES[glyph]))
	else:
		# Anything else (the OPTIONS button, or a word like "Shift" on the
		# keyboard's action row) stays text.
		badge.text = glyph
	row.add_child(badge)

	var caption := Label.new()
	caption.text = caption_text
	caption.add_theme_font_size_override("font_size", SIZE_SUPPLEMENTAL)
	caption.add_theme_color_override("font_color", TEXT_SECONDARY)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(caption)

	return row


# ---------------------------------------------------------------------------
# The app menu (home button, over a running application)
#
# THERE ARE NO STYLES LEFT IN THIS SECTION, and that is the point of keeping the
# heading. The menu is drawn over live application pixels rather than over the
# shell's own background, so it needed its own frame and its own opaque circular
# controls back when it framed the application and put two circles underneath.
# It is a centred panel of rows now (see app_overlay.gd for why), and a panel of
# rows is exactly what card_idle_box and the settings row already draw -- the
# scrim behind it does the work the opaque fills used to.
#
# overlay_card_frame, circle_box, circle_box_focused, circle_ring and
# CIRCLE_CORNER_RADIUS lived here and are gone with their only caller. The
# radius in particular was half of app_overlay's CIRCLE_SIZE, kept here so the
# two could not drift -- there is no CIRCLE_SIZE to drift from any more.

## The top-bar icon buttons, rounded to a circle. Half of TOPBAR_ICON_SIZE, so
## the corner radius meets in the middle of each edge and the square reads as a
## circle. These are now the shell's only round controls; when the menu framed
## the application there was a second, larger radius here and the two were
## deliberately not shared, because one constant would have rounded one of them
## wrong.
const TOPBAR_CIRCLE_RADIUS := TOPBAR_ICON_SIZE / 2


static func topbar_circle_box(focused: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SURFACE_FOCUS if focused else SURFACE
	box.set_corner_radius_all(TOPBAR_CIRCLE_RADIUS)
	return box


static func topbar_circle_ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(FOCUS_RING_WIDTH)
	box.border_color = FOCUS_RING
	box.set_corner_radius_all(TOPBAR_CIRCLE_RADIUS)
	return box


## Store entries carry their accent as a hex string so the hand-written data
## stays plain text. An unparseable value is a typo, not a reason to draw nothing.
static func accent(hex: String) -> Color:
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return ACCENT_FALLBACK


## The wash behind an installed app's icon, derived from its id.
##
## An enumerated application has no accent to carry -- a desktop entry has an
## icon and nothing resembling a brand colour -- but a rail of identically
## coloured cards loses the "which one am I on" cue that the hero wash gives
## the rail for free. Deriving from the id rather than randomising means a card
## keeps its colour across rescans and reboots, so the rail stays a place with
## a remembered shape rather than one that repaints itself every boot.
##
## Muted on purpose: these sit UNDER an icon, so the wash is a backdrop rather
## than the subject, and it must not fight a colourful icon drawn on top.
const APP_ACCENTS := [
	"#3E5C7A", "#4A6B52", "#7A4E63", "#8A6A3E",
	"#456B70", "#5E5183", "#8A524A", "#4A5E7E",
]


static func accent_for_id(id: String) -> Color:
	if id.is_empty():
		return ACCENT_FALLBACK
	return accent(APP_ACCENTS[absi(id.hash()) % APP_ACCENTS.size()])
