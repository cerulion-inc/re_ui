# CERULION fork of `re_ui` 0.34.1 — CER-868

This repository (`cerulion-inc/re_ui`) is a **sparse crate fork** of **upstream
`re_ui` 0.34.1** (from `rerun-io/rerun`, exactly as published to crates.io)
**plus one localized patch**. It is pinned into its one consumer, the
`cerulion-studio` native shell, via a `[patch.crates-io]` git rev in
`native/studio-shell/Cargo.toml` — the `cerulion-inc/re_grpc_server` (CER-858)
and `cerulion-inc/RustDDS` fork precedents. A consumer that gates dependency
sources with `cargo-deny` should also allow this git source in its
`deny.toml [sources]`.

The `upstream` branch holds the crates.io 0.34.1 tarball verbatim; `main` is
`upstream` plus the patch. See `README.md` for the branch model and the
`./import-upstream.sh` upgrade procedure.

## Why a fork

The Cerulion Studio native shell embeds the rerun viewer **in-process** (an
`re_viewer::App` on a shared egui `Context`) and restyles it to Studio's design
language by overriding egui `Visuals` every frame
(`native/studio-shell/src/theme.rs`). That override recolours **everything egui
itself paints from `Visuals`**.

It **cannot** reach the colours the viewer's own chrome reads **directly** from
`re_ui::DesignTokens`. `DesignTokens` is a process-global
`OnceLock<DesignTokensPerTheme>` loaded from RON **embedded in the `re_ui` crate
at compile time** (`data/dark_theme.ron` + `data/color_table.ron`, via
`include_str!`). `re_ui` exposes `design_tokens_of(theme) -> &'static
DesignTokens` (read-only) and `DesignTokens::load(theme, ron)` (constructs one,
but nothing installs it into the static) — there is **no public setter**. So the
token **values** cannot be injected at runtime; the only lever is the RON.

The Studio-target list of these fork-only surfaces is
`native/studio-shell/CANNOT-MATCH.md` (CER-856). This fork closes its rows **1, 4,
and 5** — the direct `re_ui::DesignTokens` reads. (Rows 2 + 3, the 3D/2D scene
backgrounds, are closed separately by a vizd `Background` blueprint component — no
rerun fork. Fonts are not a divergence: `re_ui` already ships Inter, Studio's UI
sans.)

## The patch (delta vs upstream 0.34.1)

**RON-only.** The only tracked change from `upstream` to `main` (besides these
fork docs, the two `LICENSE-*` files, `import-upstream.sh`, and `.gitignore`) is
four colour-token edits in `data/dark_theme.ron`. No Rust, no `Cargo.toml`, no
`data/color_table.ron`, no test changes.

All values are Studio palette colours from the single source of truth,
`cerulion-studio/native/studio-shell/palette.toml` (CER-856 — `build.rs` compiles
that file into both the egui consts and the HTML sidebar CSS vars, so the values
below are byte-identical to what the rest of Studio paints). Upstream hex values
are the resolution of the `{Gray.N}` reference through `data/color_table.ron`.

| CANNOT-MATCH row | Token (`dark_theme.ron`) | Upstream | New | palette.toml token (line) |
|---|---|---|---|---|
| 1 | `panel_bg_color` | `{Gray.100}` = `#0d0d0d` | `#10161f` | `bg-stage` (L20) |
| 4 | `notification_panel_background_color` | `{Gray.150}` = `#171717` | `#182338` | `bg-elevated` (L22) |
| 4 | `notification_background_color` | `{Gray.200}` = `#212121` | `#223047` | `border` (L29) |
| 5 | `top_bar_color` | `{Gray.100}` = `#0d0d0d` | `#10161f` | `bg-stage` (L20) |

### Row 1 — solid stage background

`panel_bg_color` is the fill behind the whole viewport when idle / letterboxed.
`re_viewer::app::ui::paint_background_fill` reads `tokens.panel_bg_color`
**directly** and over-paints egui's `panel_fill` (which `theme.rs` *does* set —
hence the override is defeated on this surface). Mapped to `bg-stage`
(`--cer-bg-stage`), Studio's app/stage background.

### Row 4 — notification toasts

`re_ui::notifications` reads both notification tokens directly. Upstream has the
list **panel** deeper (`{Gray.150}`) than each toast **card** (`{Gray.200}`).
`CANNOT-MATCH.md` names the two Studio target surfaces as `--cer-bg-elevated` and
`--cer-border`; they are mapped to **preserve that upstream ordering**:

- `notification_panel_background_color` → `bg-elevated` `#182338` (the deeper of
  the two — the panel).
- `notification_background_color` → `border` `#223047` (the brighter of the two —
  the toast card still reads raised above its panel).

`border` (`#223047`) is used here as a **surface fill**, not a stroke; it is the
elevated blue-grey the Studio palette assigns to the rung just above
`bg-elevated`, and it is exactly one of the two values `CANNOT-MATCH.md` row 4
names. (The non-fork alternative — `AppOptions.show_notification_toasts = false`
to suppress toasts entirely — was rejected in favour of restyling so the signal
is kept.)

### Row 5 — chrome that reads `tokens().X` directly (conservative subset)

`CANNOT-MATCH.md` row 5 is **polish, not correctness**: CER-853 (the bare stage)
hides this chrome, so it is not visible in the shipping Studio surface. The
instruction was to map **only** tokens with a clear palette counterpart and leave
anything ambiguous stock. Exactly one row-5 token is unambiguous:

**Mapped:**

- `top_bar_color` → `bg-stage` `#10161f`. This is a **co-reference** with
  `panel_bg_color` (row 1): both are `{Gray.100}` `#0d0d0d` upstream. Moving one
  without the other would split a single upstream colour into two Studio colours
  and seam the top bar against the panel it abuts. So this is not a new tier
  judgment — it preserves an existing upstream colour identity.

**Left stock (ambiguous tier — noted, per the conservative rule):**

| Token | Upstream | Why left stock |
|---|---|---|
| `bottom_bar_color` | `{Gray.150}` `#171717` | Upstream sits one rung above the panel; no Studio surface lands cleanly at that rung without a designer tier pick. |
| `tab_bar_color` | `{Gray.200}` `#212121` | Same — a distinct upstream rung above the bottom bar; mapping it (and only it) would introduce a blue/neutral seam against the still-stock bottom bar. |
| `blueprint_time_panel_bg_fill` | `#141326` (literal purple-black) | A distinct purple hue, not a neutral grey — no direct palette counterpart. |
| `section_header_color`, `list_item_*`, `table_*` (headers, interaction strokes, grid cards) | various `{Gray.N}` | Whole token *families*; a partial mapping seams within one widget. A coherent restyle needs a designer tier assignment across the family, out of this conservative pass's scope. |
| `viewport_background` | `{Gray.0}` `#000000` | This is the per-view scene-background fallback = `CANNOT-MATCH.md` **rows 2–3**, closed by the vizd `Background` blueprint component — explicitly out of this fork's scope. |

A further nuance: several row-5 tokens (`faint_bg_color`, `extreme_bg_color`,
`floating_color`, `text_edit_bg_color`, the `widget_*` fills) are **also** copied
into egui `Visuals` by `DesignTokens::set_colors`, and `theme.rs` already
overrides those `Visuals` fields — so their *Visuals-driven* paint is already
Studio; only their rarer *direct-token* reads keep the stock grey. They were left
stock for the same conservative reason and because the visible surface is already
handled by the shell override.

When (if) the row-5 chrome is ever un-hidden, extending the mapping is the same
sparse-RON lever, and a designer can assign the ambiguous tiers in one pass.

## `Cargo.toml` transformation — none needed

Unlike the `re_grpc_server` fork (whose patch touched `src/lib.rs`, requiring
test-literal fixes and a manifest rewrite), **this fork's patch is confined to
`data/*.ron`**. The crates.io-normalized `Cargo.toml` on `upstream` already
carries the flattened rerun workspace `[lints.*]` blocks inline and builds
standalone, so `main` keeps `Cargo.toml` **verbatim** — no field drops, no
dependency reformatting, no `clippy.toml`. The `version` stays `0.34.1`
(lockstep with the re_* graph; required for the `[patch.crates-io]` match). The
`include`/`publish` packaging fields are inert for a `git` dependency and are
left untouched.

## Light theme

Studio is dark-first. `data/light_theme.ron` is left **stock** (unpatched) — the
shell runs the dark theme, so the light tokens are never read. If a light Studio
surface is ever wanted, the same four-token edit applies there.

## Drift vs `CANNOT-MATCH.md` token names

None. All three tokens `CANNOT-MATCH.md` names explicitly — `panel_bg_color`,
`notification_panel_background_color`, `notification_background_color` — exist at
those exact names in 0.34.1's `data/dark_theme.ron` (verified against the
unpacked crate before editing). Row 5 named widget *categories* rather than
specific tokens; the `top_bar_color` / `bottom_bar_color` / `tab_bar_color`
tokens it alludes to all exist at those names. No investigation drift.

## Exit condition

Drop this fork entirely (revert the consumer to the crates.io `re_ui`, prune the
`[patch.crates-io]` rev and any `deny.toml [sources]` entry for this fork) if
`re_ui` ever exposes a **runtime setter** for its `DesignTokens` (so token
colours can be injected without editing the embedded RON).
