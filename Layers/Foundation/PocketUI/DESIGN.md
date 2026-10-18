# PocketUI design rules

Ported from the design rules of my ui-canvas project.
Values below are points in SwiftUI. Canvas batch generation, React tooling and chart
library requirements belong to ui-canvas and do not apply to the iOS package.

## Layout

| Role | Value |
| --- | --- |
| Base grid | 8 |
| Additional spacing steps | 4, 12, 20, 28 |
| Screen inset | 24 |
| Section gap | 28 |
| Label to content | 12 |
| Container padding and inner gap | 16 |
| List content padding | 12 vertical, 20 horizontal |
| Container, input and image radius | 24, continuous corners |
| Control radius | 8 or 12 |
| Static tag and inner element radius | 4 |
| Icon button and avatar | Circular |
| Interactive badge, selection and progress | Capsule |
| Button touch target | At least 44 |
| Button horizontal padding | 16 plus 4 around text |
| Button stack gap | 12 |
| Optional border | 1 |

Screen blocks use the 24-point inset or extend to the edges with content inset 24.
Horizontal rails extend to the container edges; inset their first and last items
and snap to that inset. Leave vertical space so focus rings and shadows are visible.
Keep docked bars on a solid surface or a progressive blur extending through the
safe area. Avoid a hard-edged translucent rectangle over scrolling content.

## Typography and icons

Use the system SF family, regular, medium or semibold. Scale text with Dynamic Type;
these are the default size/line-height pairs, not maximum accessibility sizes.

| Role | Size / line height |
| --- | --- |
| Caption, informational tags | 12 / 16 |
| Footnote | 14 / 18 |
| Body | 16 / 20 |
| Headline | 18 / 22 |
| Title 3 | 20 / 25 |
| Title 2 | 22 / 28 |
| Display | 24 / 28 |
| Title 1 | 28 / 34 |

Keep secondary text quieter than titles. Default page text is black / #666666 in
light mode and white / 60% white in dark mode. Native navigation chrome keeps its
system typography and sizing.

Use SF Symbols on iOS in place of the canvas's web Phosphor dependency. Use regular
weight, with fill for selected states. Icon sizes are 16 inline, 24 in navigation,
28 in lists and 12 in informational tags. Avatar sizes are 20, 40, 56 and 80.

## Color

The hex initializers come from the color extensions in my swiftux-components project.
The port retains its RGB, RRGGBB and AARRGGBB parsing and adaptive light/dark API,
with one shared UIKit parser. Keep colors in `PocketPalette`.

| Surface | Light | Dark |
| --- | --- | --- |
| Screen | #FFFFFF | #101010 |
| Detail panel and input | #F7F7F7 | #1C1C1C |
| Ink card | #1C1C1C | #1C1C1C |
| Summary and tag inset | #303030 | #303030 |
| Text on card | #FFFFFF | #FFFFFF |
| Secondary text on card | #B3B3B3 | #B3B3B3 |

The ink card stays dark in both appearances, as requested. A light screen does not
imply a light card. Do not force the whole screen into dark appearance.

## Recording card

Reference: the "ink offline footer" voice memo card in my ui-canvas project.

- Title first: 24-point semibold, followed by summary, then footer tags.
- Outer radius 24, padding 24, vertical gap 16. The selected composition overrides
  the general 16-point container padding.
- Summary inset radius 12, horizontal/top padding 16 and no bottom padding.
  This inset radius follows the selected reference rather than the general inner radius.
- Summary label 14-point semibold; text 16-point regular, at most three lines.
  A separate full-height gradient fades from clear through 30% inset tint to the
  solid inset surface. No expansion, chevron, tabs or internal controls.
- Footer tags use 12-point regular text/icons, radius 4, padding 4 vertical / 8
  horizontal, and gap 8. Stack tags when they cannot fit horizontally.
- The date tag shows the latest edit in the device locale and time zone, using
  relative day names where supported. No visible Created or Edited prefix.
  The feature currently supplies the server's `updatedAt`; unsynced local edits
  are indicated by the separate status tag until the server acknowledges them.
- The collection uses `ScrollView` and `LazyVStack` with 16-point horizontal
  container padding and 16-point card spacing. This user-requested inset overrides
  the general 24-point screen inset. Each card is wrapped in a plain `Button` that
  opens detail. Keep pull-to-refresh; expose deletion through the card context menu.
- Omit artwork and the Voice memo source label. Omit duration because the current
  model has no duration field.
- The reference's Edited offline tag requires historical edit provenance that the
  app does not store. Render actual pending, conflict or failed sync status instead;
  a synced card has only its date tag. Current airplane mode does not prove an edit
  happened offline. Do not imply the transcript has been downloaded.

## Recording detail

Use `ScrollView` with a leading-aligned `LazyVStack`, 24-point horizontal insets,
16-point vertical padding and 28-point gaps between blocks. Keep transcript segments
lazy, with 16-point gaps and 4 points between each timestamp and text. Conflict and
failure panels have 16-point padding and a 24-point radius. Labels sit 12 points
above their content; buttons stack with 12-point gaps and use an 8-point radius.

Conflict prompts and review cards use `ConflictReviewCard` for their shared
24-point shape, 16-point padding and dark gray stroke. Resolution actions use
`ConflictReviewAction`: native glass buttons with full-width, centered labels and
an 8-point control radius. Group adjacent actions in `GlassEffectContainer` with
12-point spacing. Use `PocketPalette.label` (`UIColor.label`) for primary conflict
text and action labels so they adapt to light and dark appearances. Keep secondary
labels secondary. Do not duplicate card surfaces or button styling in feature views;
`make check-conflict-review-ui` enforces these component boundaries.

Use 28-point semibold for the recording title, 18-point semibold for block headings,
16-point regular for content and inputs, 14-point regular for supporting labels and
12-point regular for timestamps/device metadata. Scale all sizes with Dynamic Type.
Keep the complete summary and transcript readable; the collection card's three-line
fade does not apply here. The edit sheet uses the same scroll layout and input style.

The screen owns its ViewModel and routes actions. Overview, transcript, failures and
conflict components take display values and callbacks; only editing/merge drafts
belong in component-local state. Keep the loaded content preview independent of the
database and live dependencies.

## Sync status

Place sync status at the leading edge of the bottom toolbar, followed by a flexible
toolbar spacer. Let the toolbar draw the item's shared glass capsule; do not add a
second `glassEffect` or hide the shared background. Only system-drawn toolbar glass
morphs into the next screen's bottom bar during navigation; a custom capsule fades
instead. Give the content 8-point horizontal padding inside that capsule. Use the
14-point regular footnote role for the phase and the 12-point regular caption role
for nonzero counts, with 4 points between rows and 8 between counts. Both fonts
scale with Dynamic Type. Omit the count row when all counts are zero.

## Content and interaction

Use actual values supplied by the feature. Sample fixtures belong only in isolated
previews. Media placeholders, when needed for new explorations, are flat colors;
do not simulate photographs with gradients or shapes. A chart should keep signed
values or labels alongside color, and meaningful axis ranges.

Prefer native buttons, navigation and scrolling. Components render values and
report actions; features own state, fetching, storage and navigation. Add motion
only when it helps explain a change, scope it to the affected view, and support
Reduce Motion. Review narrow widths, long content, both appearances and large text.
