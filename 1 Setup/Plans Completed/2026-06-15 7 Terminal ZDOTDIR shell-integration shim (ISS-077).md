---
plan: ZDOTDIR shell-integration shim
module: 7 Terminal
created: 2026-06-15
status: complete
related_issues: ISS-077
---

## Purpose
Replace the timed stdin injection of the OSC 133 shell-integration hooks with a robust, invisible `ZDOTDIR` shim, so the hooks are always installed (no race with slow `.zshrc`/`.zprofile` loads) and never echo into the user's first prompt.

## Success Condition
- Launch a terminal whose home `.zshrc` (a) defines an alias, (b) sets `PROMPT`, and (c) **clobbers** `precmd_functions=(...)` wholesale near the end. After launch:
  - The user's alias, `PATH`, and prompt are all present (real config fully loaded).
  - The OSC 133 sequences (`133;A/B/C/D`) are still emitted on each prompt/command — i.e. our hooks survived the clobber because they are appended **after** the user's `.zshrc`.
  - No snippet text is visible in the scrollback (nothing written to stdin at startup).
- A test with a home `.zshenv` that itself sets `ZDOTDIR=$HOME/.config/zsh` still loads the user's real `.zprofile`/`.zshrc`/`.zlogin` from that relocated dir, and the hooks still install.
- `swift build` clean (no new module-7 warnings); new `ZDOTDIRShim` unit tests pass; existing Terminal tests still pass.
- The shim temp directory is removed when the session ends (no accumulation across launches).

## Background — why all four dotfiles must be shadowed

Zsh reads startup files in this order, re-evaluating `$ZDOTDIR` **before each one** (defaulting to `$HOME` when unset):

1. `$ZDOTDIR/.zshenv`   (always)
2. `$ZDOTDIR/.zprofile` (login shells — we launch `zsh --login`)
3. `$ZDOTDIR/.zshrc`    (interactive shells)
4. `$ZDOTDIR/.zlogin`   (login shells)

If we point `ZDOTDIR` at a temp shim dir, zsh reads **our** files. To both (a) load the user's real config in the correct order and (b) guarantee our hooks run *after* the user's `.zshrc`, each shim file must restore the real `ZDOTDIR`, `source` the user's matching real file, then re-point `ZDOTDIR` back at the shim so the *next* shim file still runs. The user's `.zshenv` may itself reassign `ZDOTDIR`; we must re-capture that value after sourcing it and honour it for `.zprofile`/`.zshrc`/`.zlogin`, while still keeping the shim in control until after `.zshrc`.

## Steps

- [x] 1. **Add a pure shim-content generator: `7 Terminal/ZDOTDIRShim.swift`**
   What: New file (SR-6) with an `enum ZDOTDIRShim` exposing a pure, side-effect-free function that, given the real `ZDOTDIR` value, the shim directory path, a private hand-off env-var name, and the OSC 133 hook snippet, returns the text of the four files (`.zshenv`, `.zprofile`, `.zshrc`, `.zlogin`). No file I/O, no AppKit — trivially unit-testable.
   Why: Isolating the fragile shell-script generation as a pure value lets us test the exact emitted scripts without spawning a shell, and keeps `TerminalSession` focused on lifecycle (SR-6, SW-1).

- [x] 2. **Define the shim algorithm (the script each file emits)**
   What: Each shim file follows the same shape. The user's real dir is passed in via a private env var (e.g. `SPUTNIK_USER_ZDOTDIR`, defaulting to `$HOME`):
   ```sh
   # --- shim .zshenv (first file zsh reads) ---
   () {
     emulate -L zsh
     local real="${SPUTNIK_USER_ZDOTDIR:-$HOME}"
     [[ -f "$real/.zshenv" ]] && { ZDOTDIR="$real"; source "$real/.zshenv"; }
     # The user's .zshenv may have reset ZDOTDIR — re-capture and persist it.
     SPUTNIK_USER_ZDOTDIR="${ZDOTDIR:-$real}"
     # Keep the shim in control so .zprofile/.zshrc/.zlogin shims still run.
     ZDOTDIR="$SPUTNIK_SHIM_DIR"
   }
   ```
   `.zprofile` and `.zlogin` are identical but source their own real counterpart and keep `ZDOTDIR="$SPUTNIK_SHIM_DIR"`. `.zshrc` is the same **plus** appends the OSC 133 hooks after sourcing the user's real `.zshrc`, and (being the last file that matters to us) restores `ZDOTDIR` to the real value permanently:
   ```sh
   # --- tail of shim .zshrc, after sourcing the real .zshrc ---
   __sputnik_precmd() { printf '\033]133;D;%s\007' "$?"; printf '\033]133;A\007'; }
   __sputnik_preexec() { printf '\033]133;B\007'; printf '\033]133;C\007'; }
   preexec_functions+=(__sputnik_preexec)
   precmd_functions+=(__sputnik_precmd)
   ZDOTDIR="${SPUTNIK_USER_ZDOTDIR:-$HOME}"   # hand control back to the user for good
   ```
   Why: Restoring the real `ZDOTDIR` before each `source` makes the user's own config see the correct `$ZDOTDIR`; re-capturing afterward honours a user `.zshenv` that relocates it; appending hooks at the **end of `.zshrc`** guarantees they survive a wholesale `precmd_functions=(...)` reset in the user's config (the exact failure of the old timed injection). Wrapping each in an anonymous function with `emulate -L zsh` avoids leaking locals and option drift into the user's shell.

- [x] 3. **Write and own the shim directory in `TerminalSession`**
   What: In `start()`, before `PTYSpawn.spawnLoginShell`, create a unique per-session directory under `FileManager.default.temporaryDirectory` (e.g. `sputnik-zdotdir-<uuid>`), write the four files (dir `0700`, files `0600`), and store the URL in a private actor property. Resolve the real `ZDOTDIR` to pass into the generator from the inherited environment (`environment["ZDOTDIR"]`, else `$HOME`).
   Why: A per-session dir prevents collisions between windows; restrictive permissions keep other users from injecting code into our login path (SR-2). The session actor already owns launch/teardown, so it is the right owner for the temp dir lifecycle.

- [x] 4. **Point the child environment at the shim**
   What: In `buildEnvironment()` (or at the `spawnLoginShell` call site), set `environment["ZDOTDIR"] = <shim dir>`, `environment["SPUTNIK_SHIM_DIR"] = <shim dir>`, and `environment["SPUTNIK_USER_ZDOTDIR"] = <real ZDOTDIR or $HOME>`. Keep `TERM`/`COLORTERM` as today.
   Why: Setting `ZDOTDIR` at fork time is what makes zsh read our shim files first — deterministically, before any user rc runs — eliminating the 300 ms race entirely (ISS-077).

- [x] 5. **Remove the timed stdin injection**
   What: Delete `injectShellIntegration(after:)` and its call site (step 5 in `start()`, `TerminalSession.swift:166-169` / `:235-254`). The OSC 133 snippet now lives only in the `.zshrc` shim.
   Why: The timed stdin write is the root cause of ISS-077 (races slow rc loads; echoes into the first prompt). It must not coexist with the shim or the hooks would be installed twice.

- [x] 6. **Clean up the shim directory on teardown**
   What: Remove the shim directory in `cleanupPTY()` (covers exit + `terminate()`) and as a safety net in `deinit`; null out the stored URL so removal is idempotent. Remove on session end, **not** immediately after spawn, so a slow login shell still finds the files.
   Why: Avoids temp-dir accumulation across the app's lifetime (SR-3) while guaranteeing the files outlive the shell's startup reads.

- [x] 7. **Handle shim-creation failure gracefully**
   What: If creating the dir or writing any file throws, log via `SputnikLogger.terminal`, skip setting the `ZDOTDIR`/`SPUTNIK_*` env vars, and launch the shell normally **without** shell integration. Do not fall back to the timed stdin injection and do not crash (SR-2).
   Why: Shell integration is an enhancement; a transient I/O failure must never block the user from getting a working terminal, and silently re-introducing the buggy injection would defeat the fix.

- [x] 8. **Tests**
   What: Add to `7 Terminal/Tests/TerminalModuleTests.swift`:
   - `ZDOTDIRShimTests` (pure): the four generated scripts contain the expected `source` of each real counterpart, restore/re-capture `ZDOTDIR` correctly, append the OSC 133 hooks only in `.zshrc`, and embed the shim/real paths verbatim (no unescaped interpolation surprises).
   - An integration test (real PTY, under a timeout, alongside `PTYSpawnTests`): spawn `zsh --login` with `HOME` pointed at a temp fixture whose `.zshrc` defines an alias and ends with `precmd_functions=()`; assert the OSC 133 bytes appear on the master fd and the alias is defined (`alias <name>` round-trips).
   Why: The shim is shell-script-in-a-string — the highest-risk surface; a pure test pins the generated text and the integration test proves the real ordering/survival guarantees on an actual zsh.

- [x] 9. **Update the Module Guide**
   What: In `1 Setup/Module Guides/7 Terminal/guide.md`: add `ZDOTDIRShim.swift` to Source Files and the key-types list; replace the "step 5 / timed injection" description in the data-flow notes with the ZDOTDIR-shim mechanism; add an invariant ("shell integration is installed via a `ZDOTDIR` shim that re-sources the user's real dotfiles and appends OSC 133 hooks after `.zshrc`; never via timed stdin writes"); remove `ISS-077` from `open_issues`; set `status: stable`, `last_updated`/`last_verified: <completion date>`.
   Why: The guide must match the hardened code, and closing ISS-077 lets the module return to `stable` (its only open issue).

## Risks and Constraints
- **Subtle `ZDOTDIR` re-entrancy.** The whole mechanism hinges on zsh re-reading `$ZDOTDIR` before each startup file and on us re-capturing a user-relocated `ZDOTDIR`. Getting the order wrong silently breaks PATH/aliases/prompt — the Success Condition's clobber-and-relocate fixtures exist specifically to catch this.
- **No `Foundation.Process` regression.** Env vars flow through the existing `PTYSpawn.spawnLoginShell(environment:)` path (forkpty, MR-4/MR-5); this plan adds no new spawn mechanism and touches nothing in the child between fork and exec.
- **`/etc/zshenv` can override `ZDOTDIR`.** A machine-level `/etc/zshenv` that hard-sets `ZDOTDIR` runs *before* our `$ZDOTDIR/.zshenv` and would defeat the shim. This is rare and out of scope; note it in the guide's failure modes rather than working around it.
- **SR-2 / no force-unwraps.** All file I/O via `guard`/`do-catch`; failure path is step 7.
- **SR-1 / SR-5.** Pure Foundation + Darwin; no third-party packages; no cross-module reach — all changes stay inside module 7.
- **Behaviour-preserving** for the emulator/render/resize paths; only the integration-injection mechanism changes.

## Files Affected
- `7 Terminal/ZDOTDIRShim.swift` — **new**: pure generator for the four shim scripts (SR-6).
- `7 Terminal/TerminalSession.swift` — create/own/clean up the shim dir; set `ZDOTDIR`/`SPUTNIK_*` env; remove `injectShellIntegration` and its call.
- `7 Terminal/Tests/TerminalModuleTests.swift` — `ZDOTDIRShimTests` (pure) + a real-PTY integration test.
- `1 Setup/Module Guides/7 Terminal/guide.md` — shim mechanism, new file, invariant; clear ISS-077; `status: stable`.
- `1 Setup/References/Issues.md` — mark ISS-077 Resolved at closeout.

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [x] ISS-077 marked Resolved in `Issues.md`
- [x] Changes committed: `[7 Terminal] ZDOTDIR shell-integration shim`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
