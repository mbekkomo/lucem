## Lucem - a QoL wrapper over Sober
##
## Copyright (C) 2024 Trayambak Rai

import std/[os, logging, strutils]
import colored_logger
import ./[meta, argparser, config, cache_calls, desktop_files]
import ./shell/core
import ./commands/[init, run, edit_config]

proc showHelp(exitCode: int = 1) {.inline, noReturn.} =
  echo """
lucem [command] [arguments]

Commands:
  init            Install Sober
  run             Run Sober
  meta            Get build metadata
  edit-config     Edit the configuration file
  clear-cache     Clear the API caches that Lucem maintains
  shell           Launch the Lucem configuration GUI
  help            Show this message

Flags:
  --verbose, -v              Show additional debug logs, useful for diagnosing issues.
  --skip-patching, -N        Don't apply your selected patches to Roblox, use this to see if a crash is caused by them. This won't undo patches!
  --use-sober-rpc, -S        Use Sober's builtin Discord RPC that has Bloxstrap RPC. Lucem will bring this up to 1:1 feature parity soon.
  --use-sober-patching, -P   Use Sober's patches (bring back old oof) instead of Lucem's. There's no need to use this since Lucem already works just as well.
"""
  quit(exitCode)

proc showMeta() {.inline, noReturn.} =
  echo """
Lucem $1
Copyright (C) 2024 Trayambak Rai
This software is licensed under the MIT license.

* Compiled with Nim $2
* Compiled on $3

[ $4 ]

==== LICENSE ====
$5
==== LEGAL DISCLAIMER ====
Lucem is a free unofficial application that wraps around Sober, a runtime for Roblox on Linux. Lucem does not generate any revenue for its authors whatsoever.
Lucem is NOT affiliated with Roblox or its partners, nor is it endorsed by them. The Lucem developers do not support misuse of the Roblox platform and there are restrictions
in place to prevent such abuse. The Lucem developers or anyone involved with the project is NOT responsible for any damages caused by this software as it comes with NO WARRANTY.
""" %
  [
    Version,
    NimVersion,
    CompileDate & ' ' & CompileTime,
    when defined(release): "Release Build" else: "Development Build",
    LicenseString,
  ]

proc main() {.inline.} =
  addHandler(newColoredLogger())
  setLogFilter(lvlInfo)

  let input = parseInput()
  info "lucem@" & Version & " is now starting up!"

  if input.enabled("verbose", "v"):
    setLogFilter(lvlAll)

  let config = parseConfig(input)

  if config.apk.version.len > 0:
    warn "lucem: you have set up an APK version in the configuration - that feature is now deprecated as Sober now has a built-in APK fetcher."
    warn "lucem: feel free to remove it."

  case input.command
  of "meta":
    showMeta()
  of "help":
    showHelp(0)
  of "init":
    initializeSober(input)
    createLucemDesktopFile()
  of "edit-config":
    if existsEnv("EDITOR"):
      let editor = getEnv("EDITOR")
      debug "lucem: editor is `" & editor & '`'

      editConfiguration(editor, false)
    else:
      warn "lucem: you have not specified an editor in your environment variables."

      for editor in ["nano", "vscode", "vim", "nvim", "emacs", "vi", "ed"]:
        warn "lucem: trying editor `" & editor & '`'
        editConfiguration(editor)

    # validate the config on-the-go
    updateConfig(config)
  of "run":
    updateConfig(config)
    runRoblox(config)
  of "install-desktop-files":
    createLucemDesktopFile()
  of "clear-cache":
    let savedMb = clearCache()
    info "lucem: cleared cache calls to reclaim " & $savedMb & " MB of space"
  of "shell":
    initLucemShell(input)
  else:
    error "lucem: invalid command `" & input.command &
      "`; run `lucem help` for more information."

when isMainModule:
  main()
