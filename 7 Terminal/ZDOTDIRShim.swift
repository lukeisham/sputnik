import Foundation
import FoundationModule

/// Generates and installs a `ZDOTDIR` shim that makes Zsh load the user's real
/// startup files **and** install Sputnik's OSC 133 shell-integration hooks — without
/// the timed-stdin injection that raced slow rc loads and echoed into the first
/// prompt (ISS-077).
///
/// ## Why a shim
/// Zsh reads startup files in a fixed order, re-evaluating `$ZDOTDIR` (default
/// `$HOME`) **before each one**:
///
/// 1. `$ZDOTDIR/.zshenv`   — always
/// 2. `$ZDOTDIR/.zprofile` — login shells
/// 3. `$ZDOTDIR/.zshrc`    — interactive shells
/// 4. `$ZDOTDIR/.zlogin`   — login shells
///
/// Pointing `ZDOTDIR` at a temp directory of our files lets us run code around the
/// user's config. To both load the user's real files in order **and** guarantee our
/// hooks run *after* `.zshrc` (so a wholesale `precmd_functions=(...)` reset in the
/// user's config cannot drop them), each shim file:
///
/// 1. restores `ZDOTDIR` to the user's real value,
/// 2. `source`s the user's matching real file,
/// 3. re-captures `ZDOTDIR` in case the user's file relocated it, then
/// 4. re-points `ZDOTDIR` back at the shim so the **next** shim file still runs.
///
/// `.zshrc` additionally appends the OSC 133 hooks and leaves `ZDOTDIR` restored to
/// the real value permanently; `.zlogin`'s shim covers the rare non-interactive
/// login shell where `.zshrc` is skipped.
///
/// ## No path interpolation
/// The shim dir and the user's real `ZDOTDIR` are passed to the child **as
/// environment variables** (`SPUTNIK_SHIM_DIR`, `SPUTNIK_USER_ZDOTDIR`), not
/// interpolated into the script text. The four scripts are therefore constant and
/// free of any shell-quoting hazard around the user's paths (SR-2).
enum ZDOTDIRShim {

    // MARK: - Hand-off environment variables

    /// Absolute path of the shim directory. The child's `ZDOTDIR` is also set to
    /// this so Zsh reads our files first; the shim scripts re-point `ZDOTDIR` back
    /// to it after sourcing each real file.
    static let shimDirVar = "SPUTNIK_SHIM_DIR"

    /// The user's real `ZDOTDIR` (their own `ZDOTDIR` if set before launch, else
    /// `$HOME`). The shim restores this before sourcing each real startup file.
    static let userZDOTDIRVar = "SPUTNIK_USER_ZDOTDIR"

    // MARK: - Generated scripts

    /// The text of the four shim startup files.
    struct Contents: Equatable {
        let zshenv: String
        let zprofile: String
        let zshrc: String
        let zlogin: String
    }

    /// The OSC 133 shell-integration hooks, appended to the `.zshrc` shim **after**
    /// the user's real `.zshrc` so a `precmd_functions=(...)` reset cannot drop them.
    /// `typeset -ga` guarantees the arrays exist as global arrays even if the user's
    /// config unset them.
    static let osc133Hooks = """
        __sputnik_precmd() {
            printf '\\033]133;D;%s\\007' "$?"
            printf '\\033]133;A\\007'
        }
        __sputnik_preexec() {
            printf '\\033]133;B\\007'
            printf '\\033]133;C\\007'
        }
        typeset -ga precmd_functions preexec_functions
        preexec_functions+=(__sputnik_preexec)
        precmd_functions+=(__sputnik_precmd)
        """

    /// Builds one shim file that restores the real `ZDOTDIR`, sources the user's real
    /// `dotfile`, re-captures any relocation, then leaves `ZDOTDIR` at `finalTarget`
    /// (`shim` to chain to the next file, or `real` to hand control back for good).
    private static func shimFile(
        dotfile: String,
        finalTarget: FinalTarget
    ) -> String {
        let restore: String
        switch finalTarget {
        case .shim:
            // Re-capture a user-relocated ZDOTDIR, then chain to the next shim file.
            restore = """
              \(userZDOTDIRVar)="${ZDOTDIR:-$real}"
              ZDOTDIR="${\(shimDirVar):?SPUTNIK_SHIM_DIR unset}"
            """
        case .real:
            // Terminal file: re-capture, then hand ZDOTDIR back to the user for good.
            restore = """
              \(userZDOTDIRVar)="${ZDOTDIR:-$real}"
              ZDOTDIR="$\(userZDOTDIRVar)"
            """
        }
        return """
            () {
              emulate -L zsh
              local real="${\(userZDOTDIRVar):-$HOME}"
              ZDOTDIR="$real"
              [[ -f "$real/\(dotfile)" ]] && source "$real/\(dotfile)"
            \(restore)
            }
            """
    }

    private enum FinalTarget { case shim, real }

    /// Returns the four shim scripts. Pure — no file system access — so the exact
    /// emitted text is unit-testable without spawning a shell.
    static func contents() -> Contents {
        Contents(
            zshenv: shimFile(dotfile: ".zshenv", finalTarget: .shim),
            zprofile: shimFile(dotfile: ".zprofile", finalTarget: .shim),
            // `.zshrc` is the last file that matters to us in an interactive login
            // shell: source the real one, append the hooks, then restore ZDOTDIR.
            zshrc: shimFile(dotfile: ".zshrc", finalTarget: .real) + "\n" + osc133Hooks,
            // `.zlogin`'s shim only runs for the rare non-interactive login shell
            // (where `.zshrc` was skipped); restore + source so the user's real
            // `.zlogin` still loads.
            zlogin: shimFile(dotfile: ".zlogin", finalTarget: .real)
        )
    }

    // MARK: - Installation

    /// Writes the four shim files into a fresh, private temp directory and returns
    /// its URL. The caller passes the directory to the child via `ZDOTDIR` +
    /// `SPUTNIK_SHIM_DIR` and removes it on session teardown.
    ///
    /// - Throws: any `FileManager`/`Data.write` error if the directory or a file
    ///   cannot be created — the caller treats this as "launch without integration"
    ///   rather than failing the terminal (SR-2).
    static func install() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sputnik-zdotdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let scripts = contents()
        let files: [(name: String, body: String)] = [
            (".zshenv", scripts.zshenv),
            (".zprofile", scripts.zprofile),
            (".zshrc", scripts.zshrc),
            (".zlogin", scripts.zlogin),
        ]
        for file in files {
            let url = directory.appendingPathComponent(file.name)
            guard let data = (file.body + "\n").data(using: .utf8) else { continue }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return directory
    }
}
