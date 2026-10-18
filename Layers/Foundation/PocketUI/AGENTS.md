# PocketUI

Read [DESIGN.md](DESIGN.md) before adding or changing components. It ports the
ui-canvas design rules to native SwiftUI, including the selected recording card.

- Keep components independent of Domain, persistence, networking and screen navigation.
  Receive display values; let the feature own actions.
- Use the shared `PocketPalette` and `Color(hex:)` / `Color(lightHex:darkHex:)` helpers.
- Use real feature data. Do not invent durations, categories, offline history or
  download availability to fill a design.
- Group a type and its extension files inside a folder named after the type.
