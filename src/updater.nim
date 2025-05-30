## Lucem auto-updater
## Copyright (C) 2024 Trayambak Rai
import std/[os, osproc, logging, tempfiles, distros, posix]
import pkg/[semver, jsony]
import ./[http, argparser, config, sugar, meta, notifications, desktop_files, systemd]
import ./commands/init

type
  ReleaseAuthor* = object
    login*: string
    id*: uint32
    node_id*, avatar_url*, gravatar_id*, url*, html_url*, followers_url*, following_url*, gists_url*, starred_url*, subscriptions_url*, organizations_url*, repos_url*, events_url*, received_events_url*, `type`*, user_view_type*: string
    site_admin*: bool

  LucemRelease* = object
    url*, assets_url*, upload_url*, html_url*: string
    id*: uint64
    author*: ReleaseAuthor
    node_id*, tag_name*, target_commitish*, name*: string
    draft*, prerelease*: bool
    created_at*, published_at*: string
    assets*: seq[string]
    tarball_url*, zipball_url*: string

const
  LucemReleaseUrl {.strdefine.} = "https://api.github.com/repos/xTrayambak/lucem/releases/latest"

proc getLatestRelease*(): Option[LucemRelease] {.inline.} =
  debug "lucem: auto-updater: fetching latest release"
  try:
    return httpGet(
      LucemReleaseUrl
    ).fromJson(
      LucemRelease
    ).some()
  except JsonError as exc:
    warn "lucem: auto-updater: cannot parse release data: " & exc.msg
  except CatchableError as exc:
    warn "lucem: auto-updater: cannot get latest release: " & exc.msg & " (" & $exc.name & ')'

proc runUpdateChecker*(config: Config) =
  if not config.lucem.autoUpdater:
    debug "lucem: auto-updater: skipping update checks as auto-updater is disabled in config"
    return

  when defined(lucemDisableAutoUpdater):
    debug "lucem: auto-updater: skipping update checks as auto-updater is disabled by a compile-time flag (--define:lucemDisableAutoUpdater)"
    return

  debug "lucem: auto-updater: running update checks"
  let release = getLatestRelease()

  if !release:
    warn "lucem: auto-updater: cannot get release, skipping checks."
    return

  let data = &release
  let newVersion = try:
    parseVersion(data.tagName).some()
  except semver.ParseError as exc:
    warn "lucem: auto-updater: cannot parse new semver: " & exc.msg & " (" & data.tagName & ')'
    none(semver.Version)

  if !newVersion:
    return

  let currVersion = parseVersion(meta.Version)

  debug "lucem: auto-updater: new version: " & $(&newVersion)
  debug "lucem: auto-updater: current version: " & $currVersion

  let newVer = &newVersion

  if newVer > currVersion:
    info "lucem: found a new release! (" & $newVer & ')'
    presentUpdateAlert(
      "Lucem " & $newVer & " is out!",
      "A new version of Lucem is out. You are strongly advised to update to this release for bug fixes and other improvements. Press Enter to update. Press any other key to close this dialog.", blocks = true
    )
  elif newVer == currVersion:
    debug "lucem: user is on the latest version of lucem"
  elif newVer < currVersion:
    warn "lucem: version mismatch (newest release: " & $newVer & ", version this binary was tagged as: " & $currVersion & ')'
    warn "lucem: are you using a development version? :P"

proc postUpdatePreparation =
  info "lucem: beginning post-update preparation"

  debug "lucem: killing any running lucem instances and lucemd"

  # FIXME: Use POSIX APIs for this.
  discard execCmd("kill $(pidof lucemd)")
  discard execCmd("kill $(pidof lucem)")
  
  debug "lucem: initializing lucem"
  initializeSober(default(Input))
  createLucemDesktopFile()
  installSystemdService()

  info "lucem: completed post-update preparation"

proc updateLucem* =
  info "lucem: checking for updates"
  let release = getLatestRelease()
  
  if !release:
    error "lucem: cannot get current release"
    return

  let currVersion = parseVersion(meta.Version)
  let newVer = parseVersion((&release).tagName)

  if newVer != currVersion:
    info "lucem: found new version! (" & $newVer & ')'
    let wd = getCurrentDir()
    let tmpDir = createTempDir("lucem-", '-' & $newVer)
    
    let git = findExe("git")
    let nimble = findExe("nimble")

    if nimble.len < 1:
      error "lucem: cannot find `nimble`!"
      quit(1)

    if git.len < 1:
      error "lucem: cannot find `git`!"
      quit(1)
    
    info "lucem: cloning source code"
    if (let code = execCmd(git & " clone https://github.com/xTrayambak/lucem.git " & tmpDir); code != 0):
      error "lucem: git exited with non-zero exit code: " & $code
      quit(1)

    discard chdir(tmpDir.cstring)
    
    info "lucem: switching to " & $newVer & " branch"
    if (let code = execCmd(git & " checkout " & $newVer); code != 0):
      error "lucem: git exited with non-zero exit code: " & $code
      quit(1)
    
    info "lucem: compiling lucem"
    if not detectOs(NixOS):
      if (let code = execCmd(nimble & " install"); code != 0):
        error "lucem: nimble exited with non-zero exit code: " & $code
        quit(1)
    else:
      info "lucem: Nix environment detected, entering Nix shell"
      let nix = findExe("nix-shell") & "-shell" # FIXME: for some reason, `nix-shell` returns the `nix` binary instead here. Perhaps a Nim STL bug
      if nix.len < 1:
        error "lucem: cannot find `nix-shell`!"
        quit(1)

      if (let code = execCmd(nix & " --run \"" & nimble & " install\""); code != 0):
        error "lucem: nix-shell or nimble exited with non-zero exit code: " & $code
        quit(1)

    info "lucem: updated successfully!"
    info "Lucem is now at version " & $newVer

    postUpdatePreparation()
  else:
    info "lucem: nothing to do."
    quit(0)
