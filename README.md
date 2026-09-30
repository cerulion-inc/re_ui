# `re_ui` — Cerulion sparse fork

A **sparse crate fork** of [`re_ui`](https://crates.io/crates/re_ui) `0.34.1`
(from [`rerun-io/rerun`](https://github.com/rerun-io/rerun)) carrying **one
localized Cerulion patch**: a handful of design-token colour edits in
`data/dark_theme.ron` that restyle the parts of the embedded rerun viewer's
chrome that `re_ui` paints **directly from its static `DesignTokens`** (loaded
from RON at compile time, no runtime setter) — the surfaces the Cerulion Studio
shell's egui `Visuals` override provably cannot reach. Tracked in **CER-868**.
The full delta is in [`CERULION-PATCH.md`](./CERULION-PATCH.md).

**The patch is RON-only** — no Rust, no `Cargo.toml`, no test changes. It edits
`data/*.ron` (the files `re_ui` `include_str!`s at build time), so the compiled
crate's behaviour is identical to upstream except for the token colour values.
This makes it an even smaller fork than the `re_grpc_server` precedent below.

This is a *single-crate* fork (one crate at the repo root), not a fork of the
whole rerun monorepo. Its one consumer, `cerulion-studio`, pins it as a `git`
`[patch.crates-io]` rev in `native/studio-shell/Cargo.toml` — the same model as
[`cerulion-inc/re_grpc_server`](https://github.com/cerulion-inc/re_grpc_server)
(CER-858) and [`cerulion-inc/RustDDS`](https://github.com/cerulion-inc/RustDDS)
— keeping cold-CI git-clone weight to this one small crate instead of rerun's
~278 MB monorepo.

## What the patch fixes

`re_ui::DesignTokens` is a process-global `OnceLock`, loaded from RON embedded in
the crate at compile time, with **no public setter**. So the Studio shell (which
overrides egui `Visuals` on the shared `Context`) cannot inject these token
values at runtime — the only lever is the RON. The patched tokens (dark theme):

| CER-856 `CANNOT-MATCH.md` row | Token(s) | Studio surface |
|---|---|---|
| 1 — solid stage background | `panel_bg_color` | `--cer-bg-stage` |
| 4 — notification toasts | `notification_panel_background_color`, `notification_background_color` | `--cer-bg-elevated`, `--cer-border` |
| 5 — chrome that reads tokens directly | `top_bar_color` (conservative subset) | `--cer-bg-stage` |

Values come from Studio's single-source-of-truth palette,
`native/studio-shell/palette.toml`. See `CERULION-PATCH.md` for the per-token
old→new mapping and citations, and for which row-5 tokens were deliberately left
stock (ambiguous tier — CER-853 hides that chrome, so it is polish).

Rows 2 + 3 (the 3D / 2D scene backgrounds) are **not** in this fork's scope — they
are closed by a vizd `Background` blueprint component (no rerun fork). Fonts are
not in scope (`re_ui` already ships Inter, Studio's UI sans).

## Branch model

| Branch | Contents |
|---|---|
| `upstream` | The crates.io `re_ui` 0.34.1 tarball **verbatim** at repo root (packaging artifacts `.cargo_vcs_info.json` / `Cargo.toml.orig` stripped). Tagged `upstream/0.34.1`. |
| `main` | `upstream` + the Cerulion patch. This is the branch consumers pin. |

Keeping the pristine upstream tree on its own branch makes the Cerulion delta a
reviewable `git diff upstream..main` (which touches only `data/dark_theme.ron` +
the fork docs) and makes version bumps a clean merge.

## Upgrading to a new upstream release

```sh
# 1. Refresh the upstream branch to the new crates.io tarball + tag it.
VERSION=0.35.0
./import-upstream.sh "$VERSION"

# 2. Before merging, main must contain the rev Studio pins now. PINNED is the
#    full re_ui rev in cerulion-studio's native/studio-shell/Cargo.toml
#    [patch.crates-io]. If main lacks it, the merge drops Studio's current
#    tokens: stop and bring that rev onto main first. Otherwise bring the patch
#    forward onto main (resolve any conflicts in the RON), then publish both
#    branches and the new upstream tag so Studio can fetch the rev.
git checkout main
if git merge-base --is-ancestor "$PINNED" main; then
    git merge upstream && git push origin upstream main "refs/tags/upstream/$VERSION"
else
    echo "stop: bring the pinned rev onto main first" >&2
fi

# 3. In cerulion-studio, bump the re_ui rev in native/studio-shell/Cargo.toml
#    [patch.crates-io] to the new main head (git rev-parse main here), then
#    rebuild and run the shell tests (tests/reui_fork_pin.rs must pass). Commit
#    the bump together with the regenerated native/studio-shell/Cargo.lock.

# 4. Once that bump is committed, point the pin/cerulion-studio tag in this
#    repository at the same rev and publish it. A moved tag reaches the remote
#    only with a forced push. REV is the full rev Studio now pins.
git tag -f pin/cerulion-studio "$REV"
git push --force origin refs/tags/pin/cerulion-studio
```

`import-upstream.sh` downloads the crates.io tarball for the given version,
replaces the tree on the `upstream` branch, commits, and tags `upstream/<version>`.
The version stays lockstep with the rest of the re_* graph (`cargo tree | grep re_`).

## Exit condition

Drop this fork (revert the consumer to the crates.io `re_ui`) if `re_ui` ever
exposes a runtime setter for its `DesignTokens` (so token colours can be injected
without touching the RON). See `CERULION-PATCH.md`.

## License

Same as upstream rerun: dual-licensed under [MIT](./LICENSE-MIT) or
[Apache-2.0](./LICENSE-APACHE), at your option; the bundled Inter font is
OFL-1.1 (`data/OFL.txt`).
