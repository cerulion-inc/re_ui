# CERULION fork of `re_ui` 0.34.1 — CER-868 (+ CER-882)

This repository (`cerulion-inc/re_ui`) is a **sparse crate fork** of **upstream
`re_ui` 0.34.1** (from `rerun-io/rerun`, exactly as published to crates.io)
**plus one localized patch**. It is pinned into the consumer (`cerulion-studio`'s
native shell, and if pinned there `cerulion-base`) via a root `Cargo.toml`
`[patch.crates-io]` git rev — the `cerulion-inc/re_grpc_server` (CER-858) and
`cerulion-inc/RustDDS` fork precedents — and allow-listed in the consumer's
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
**five** colour-token edits in `data/dark_theme.ron` (four from CER-868, one
added by CER-882). No Rust, no `Cargo.toml`, no `data/color_table.ron`, no test
changes.

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
| 5 | `tab_bar_color` (CER-882) | `{Gray.200}` = `#212121` | `#0c1219` | `bg-header` (L21) |

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
anything ambiguous stock. CER-868 mapped the one token that was unambiguous then
(`top_bar_color`); CER-882 adds `tab_bar_color`, whose deferral rested on a
premise that turned out to be false (see below). Everything else stays stock:

**Mapped:**

- `top_bar_color` → `bg-stage` `#10161f`. This is a **co-reference** with
  `panel_bg_color` (row 1): both are `{Gray.100}` `#0d0d0d` upstream. Moving one
  without the other would split a single upstream colour into two Studio colours
  and seam the top bar against the panel it abuts. So this is not a new tier
  judgment — it preserves an existing upstream colour identity.

- `tab_bar_color` → `bg-header` `#0c1219` (**CER-882**). This is the
  **stage-top band**: `re_viewport`'s `TabViewer::tab_bar_color` reads this token
  directly, and `egui_tiles` fills the entire view-tab strip with it
  (`container/tabs.rs::tab_bar_ui` → `painter().rect_filled(max_rect, …,
  behavior.tab_bar_color(..))`). In the Studio shell that strip is the **only**
  rerun chrome still visible at the top of the bare stage, and it abuts the
  sidebar's `bg-header` `#0c1219` header across the shell's 1px divider — two
  chrome bands meeting at one seam, reading as two different tones (cool
  blue-black vs the warm neutral `#212121`). Mapping it to `bg-header` makes the
  window's top chrome ONE surface.

  It is *deeper* than `panel_bg_color` (`#10161f`) by design: that is Studio's
  chrome grammar (chrome bands sit under content — the sidebar's header and
  status bar are `bg-header` under a `bg-stage` list), and `egui_tiles` paints an
  ACTIVE tab from `visuals.panel_fill`, so the active tab still lifts out of the
  bar and connects to the stage below it.

  Also reached by this token: `egui_tiles::Behavior::resize_stroke` paints the
  **idle gap between side-by-side tiles** with `tab_bar_color`, so the seams
  between views stop being warm-grey lines across a cool blue-black stage.

  **Why CER-868 deferred it, and why that no longer holds.** CER-868 left this
  token stock on the grounds that mapping it alone "would introduce a
  blue/neutral seam against the still-stock bottom bar". There is no such seam
  — but **not** because `bottom_bar_color` is unused. It is genuinely read:
  `re_ui::DesignTokens::bottom_panel_frame()` takes it as the returned frame's
  `fill` (`src/design_tokens.rs`), and `re_viewer` 0.34.1 calls that helper at
  four sites. Three of them replace `fill` immediately, so the token never
  reaches the screen through them:

  | Call site | What it paints | Fill actually used |
  |---|---|---|
  | `re_viewer/src/app_state.rs` (blueprint time panel) | blueprint timeline | `.fill(blueprint_time_panel_bg_fill)` |
  | `re_viewer/src/app/ui.rs` (`dev_panel_ui`) | dev panel | `ui.visuals().panel_fill` |
  | `re_viewer/src/ui/mobile_warning_ui.rs` | iOS/Android warning banner | `ui.visuals().panel_fill` |
  | `re_viewer/src/app_state.rs` (time panel) | **time panel / streams view** | **`bottom_bar_color`** |

  So it survives to the screen at exactly one surface — and Studio's bare stage
  pins `panel_state_overrides.time = Some(PanelState::Hidden)` (CER-853,
  `native/studio-shell/src/bare_stage.rs`), while
  `re_time_panel::TimePanel::show_panel` early-returns on `state.is_hidden()`.
  That surface therefore never paints in the default Studio UI; it is reachable
  only via the `STUDIO_SHELL_DEBUG_UI=1` escape hatch, where the rest of the
  stock chrome is back anyway. It stays stock: there is nothing visible to seam
  against, and (per the row below) upstream's rung has no clean Studio tier.

**Left stock (ambiguous tier — noted, per the conservative rule):**

| Token | Upstream | Why left stock |
|---|---|---|
| `bottom_bar_color` | `{Gray.150}` `#171717` | Read by `bottom_panel_frame()`, but it survives un-overridden at exactly one `re_viewer` call site — the time panel / streams view (see the four-site table above) — and CER-853's bare stage pins that panel `Hidden`, so it never paints in the default Studio UI. Upstream also sits one rung above the panel with no clean Studio tier. Mapping it would move nothing visible. |
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
`[patch.crates-io]` rev and the `deny.toml [sources]` entry) if `re_ui` ever
exposes a **runtime setter** for its `DesignTokens` (so token colours can be
injected without editing the embedded RON).
