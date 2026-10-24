//
//  ShellIntegration.swift
//  Gridline
//
//  Script kecil yang disuntikkan ke proses shell zsh supaya mengirim OSC 7
//  (`\e]7;file://host/path\a`) setiap kali prompt baru ditampilkan, sehingga
//  Gridline bisa melacak cwd tab terminal untuk Cmd+klik (apps-spec.md
//  bagian 8 & 9). Tidak menyentuh dotfile pengguna: dotfile asli tetap
//  disource lewat `GRIDLINE_USER_ZDOTDIR`, dan `ZDOTDIR` dikembalikan ke
//  nilai asli di akhir `.zshrc` supaya shell/proses anak berikutnya (mis.
//  `zsh` atau `ssh` bersarang) tidak ikut memakai dotfile Gridline.
//
//  Shell selain zsh belum didukung — `environmentOverrides` mengembalikan
//  array kosong, dan Cmd+klik tetap fallback ke folder repo sesuai
//  apps-spec.md bagian 9.
//

import Foundation

enum ShellIntegration {
    /// Direktori `ZDOTDIR` pengganti untuk shell zsh yang dibuat Gridline.
    /// Ditulis sekali per peluncuran aplikasi (idempoten, konten statis).
    static let zshDirectory: String = {
        let base = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/Gridline/shell-integration/zsh")
        writeZshFiles(to: base)
        return base
    }()

    /// Variabel lingkungan tambahan untuk mengaktifkan integrasi, atau `[]`
    /// jika shell-nya bukan zsh.
    static func environmentOverrides(forShellNamed shellName: String, commandStatePath: String) -> [String] {
        guard shellName == "zsh" else { return [] }
        let originalZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
        let cliColor = ProcessInfo.processInfo.environment["CLICOLOR"] ?? "1"
        let lsColors = ProcessInfo.processInfo.environment["LSCOLORS"] ?? "ExFxCxDxBxegedabagacad"
        return [
            "GRIDLINE_USER_ZDOTDIR=\(originalZdotdir)",
            "GRIDLINE_COMMAND_STATE_FILE=\(commandStatePath)",
            "CLICOLOR=\(cliColor)",
            "LSCOLORS=\(lsColors)",
            "ZDOTDIR=\(zshDirectory)",
        ]
    }

    /// Mengubah payload OSC 7 (`file://host/path`, path persen-encoded)
    /// menjadi path filesystem biasa.
    static func parseOSC7(_ payload: String) -> String? {
        guard let url = URL(string: payload), url.scheme == "file" else { return nil }
        return url.path
    }

    private static func writeZshFiles(to directory: String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        func sourceUserFile(_ name: String) -> String {
            #"""
            [ -n "$GRIDLINE_USER_ZDOTDIR" ] && [ -f "$GRIDLINE_USER_ZDOTDIR/\#(name)" ] && source "$GRIDLINE_USER_ZDOTDIR/\#(name)"
            """#
        }

        write(sourceUserFile(".zshenv"), to: directory, name: ".zshenv")
        write(sourceUserFile(".zprofile"), to: directory, name: ".zprofile")
        write(sourceUserFile(".zlogin"), to: directory, name: ".zlogin")

        let zshrc = sourceUserFile(".zshrc") + "\n" + #"""

        # Gridline: lapor cwd lewat OSC 7 setiap prompt baru, dengan PWD
        # dipersen-encode (path berisi spasi/unicode tetap aman).
        __gridline_report_cwd() {
            emulate -L zsh
            if [[ -n "$GRIDLINE_COMMAND_STATE_FILE" ]]; then
                print -r -- idle >| "$GRIDLINE_COMMAND_STATE_FILE"
            fi
            local url_path="" i ch hexch
            for (( i = 1; i <= ${#PWD}; ++i )); do
                ch="$PWD[i]"
                if [[ "$ch" == [A-Za-z0-9_.~/-] ]]; then
                    url_path+="$ch"
                else
                    hexch=$(printf "%02X" "'$ch")
                    url_path+="%$hexch"
                fi
            done
            printf '\e]7;file://%s%s\a' "${HOST:-localhost}" "$url_path"
        }
        precmd_functions+=(__gridline_report_cwd)

        # Track activity without recording the command text so closing an idle
        # shell prompt does not show a warning.
        __gridline_mark_command_running() {
            emulate -L zsh
            if [[ -n "$GRIDLINE_COMMAND_STATE_FILE" ]]; then
                print -r -- running >| "$GRIDLINE_COMMAND_STATE_FILE"
            fi
        }
        preexec_functions+=(__gridline_mark_command_running)

        # Add a colored prompt only when the user's shell kept zsh's default.
        # A prompt configured in the user's own .zshrc remains untouched.
        if [[ "$PROMPT" == "%m%#" || "$PROMPT" == "%m%# " ]]; then
            PROMPT='%F{white}%n@%m%f %F{green}%~%f %# '
        fi

        # Kembalikan ZDOTDIR ke nilai asli supaya shell/proses anak
        # berikutnya tidak ikut memakai dotfile Gridline.
        if [ -n "$GRIDLINE_USER_ZDOTDIR" ]; then
            export ZDOTDIR="$GRIDLINE_USER_ZDOTDIR"
            unset GRIDLINE_USER_ZDOTDIR
        fi

        """#
        write(zshrc, to: directory, name: ".zshrc")
    }

    private static func write(_ content: String, to directory: String, name: String) {
        let path = (directory as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
