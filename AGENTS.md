# Enforced Swift conventions

| Rule | Enforcement |
| --- | --- |
| Omit redundant member access modifiers inside an extension that already supplies that access level, for example `public static` inside `public extension`. | SwiftFormat `redundantExtensionACL`; `make format` fixes it and `make check-swift-access` rejects it locally and in CI. |
| Packagebot declares a resource bundle only when that target contains resource files. Empty folders do not need bundles. | `make check-package-resources` exercises resource-free, empty, hidden, nested and named-target fixtures locally and in CI. |
| Verify simulator builds with normal code signing so resource bundle signing failures are caught. | `make build` runs the same simulator build locally and in CI. |
| Keep a split Swift type's declaration and `Type+*.swift` extension files together in one `Type/` folder. | `make check-swift-file-groups` derives groups from filenames and rejects scattered files during lint, preflight and CI. |
| Render conflict cards through `ConflictReviewCard` and their actions through `ConflictReviewAction`, which own the shared stroke, centered full-width glass buttons and adaptive `UIColor.label` text. | `make check-conflict-review-ui` rejects raw buttons and fixed text colors in conflict cards, verifies rejection of the pre-fix field/delete sources, and runs during lint, preflight and CI. |
