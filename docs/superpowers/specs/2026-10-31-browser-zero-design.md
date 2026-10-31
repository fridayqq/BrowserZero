# Browser Zero — design

Date: 2026-10-31
Status: approved direction (user: "Делай"), MVP scope = items 1–5 below.

## Intent

A macOS "browser chooser" that replaces Browserino for the user. Instead of asking *which
browser*, it asks *where* — a browser **or a specific space/profile inside it** (Arc space,
Zen workspace, Chromium profile) — and tries to already know the answer, so most links open
with a single Enter (or with no picker at all, via rules).

The user works across several contexts (Personal, Dev = work, SL, A) that exist in parallel in
Arc, Zen and Dia. Links arrive from Teams/Outlook (work, Microsoft SafeLinks), Telegram, terminal,
etc. Browserino can't target spaces, can't see the source app, and doesn't learn.

Prior art: Browserino (we forked it and added spaces — `~/code/Browserino`, branch `spaces`;
reuse its discovery/opening code, it is verified against the user's real data).

## Goals (MVP)

1. **Targets are first-class.** A target = browser + optional profile. Every discovered
   Arc space / Zen workspace / Chromium profile is its own row ("Arc · Dev"), plus a plain row
   per browser. Discovery is automatic.
2. **Rules by URL and by source app.** e.g. "from Teams/Outlook → Arc · Dev",
   "`*.atlassian.net` → Arc · Dev". A matching rule opens immediately, no picker.
3. **Learning.** Remember choices; preselect the most likely target for this host + source app.
   After the same target is chosen for a host 3 times in a row, offer inline
   "Always open <host> in <target>?" → creates a rule.
4. **Type-to-filter.** Typing in the picker fuzzy-filters targets; Enter opens the top/selected one.
5. **Link cleaning.** Unwrap redirect wrappers and strip tracking params before matching and
   opening.

## Later (not MVP — keep the architecture open for them)

- Hotkey: take the current tab URL from the frontmost browser and reopen it elsewhere.
- Recent links history in the menu bar, re-open in another target.
- Config as hand-editable TOML file.
- Opening in native apps (Zoom, Figma, Teams, Jira).

## Non-goals

- Private/incognito mode (only if asked later).
- Sync between machines.
- Manual drag-and-drop ordering of browsers (order comes from usage).
- Shipping via Homebrew / notarization. Local ad-hoc-signed build is enough.

## Anti-goals (failure even if it "works")

- **A link is ever lost.** Every failure path (AppleScript error, missing extension, unreadable
  data) must fall back to opening the URL in the target's browser normally.
- The picker feels slower than Browserino. It must appear instantly at the cursor; discovery
  runs in the background from cache, never blocks the picker.
- Breaking the user's default-browser setup. Browserino stays installed until the user switches.

## Constraints (verified in this session)

- **No Xcode**, only Command Line Tools (Swift 6.4). Build must work with
  `swift build` + a script that assembles and ad-hoc signs the `.app`.
- **SDK:** with the macOS 27 SDK, SwiftUI's `@State` resolves to a macro whose plugin is
  missing in CLT → compile error. Build against `MacOSX26.5.sdk`
  (`/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`). `#Preview` macros are also
  unavailable — don't use them. `scrollEdgeEffectDisabled` was renamed `scrollEdgeEffectHidden`.
  Regex literals need `-enable-bare-slash-regex` (SwiftPM: `swiftSettings`, or avoid literals).
- Tests: **Swift Testing** (`import Testing`) works under CLT with
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift test` (verified).
  XCTest does **not** build under CLT — don't use it.
- Machine: Apple Silicon, macOS 27. Min deployment target: macOS 14.
- Different bundle id from Browserino: `dev.fridayqq.BrowserZero` (my call), so both can coexist.

## How it works (decided)

### Discovery (port from fork `Browserino/Models/BrowserProfile.swift`)

- Browsers: `NSWorkspace.urlsForApplications(toOpen: https:)`, minus self and non-browsers
  that register https (iTerm, ChatGPT, Codex…). Hidden list editable in settings.
- **Arc** (`company.thebrowser.Browser`): `~/Library/Application Support/Arc/StorableSidebar.json`
  → `sidebar.containers[].spaces[]` dicts with `title`. Dedupe by title.
- **Zen** (`app.zen-browser.zen`): profile from `zen/profiles.ini` (`[Install…] Default=`),
  `zen-sessions.jsonlz4` (mozLz4: 8-byte magic `mozLz40\0`, uint32 LE size, raw LZ4 block —
  decode with `Compression` `COMPRESSION_LZ4_RAW`) → `spaces[]` {name, icon, containerTabId}.
  Container names from `containers.json` identities; built-in ids 1–4 have no name →
  Personal/Work/Banking/Shopping. A workspace with `containerTabId == 0` is shown as
  "needs container" and is not selectable.
- **Chromium** (Chrome, Brave, Edge, Vivaldi, Opera, Yandex, Comet, Dia — map of bundle id →
  App Support dir is in the fork): `Local State` → `profile.info_cache` + `profiles_order`;
  only when >1 profile. Chrome's data is unreadable without Full Disk Access (verified) →
  keep last known profiles; show a hint pointing to FDA.
- If a source can't be read, keep the previously cached profiles for that browser.
- Cache discovered targets on disk; refresh at launch, when picker opens (async), and on demand.

### Opening

- **Arc space:** NSAppleScript on a background serial queue:
  `tell application "Arc"` → ensure a window → `tell front window` → `tell space "<title>"` →
  `focus` + `make new tab with properties {URL:"…"}` → `activate`. Escape `\` and `"`.
  Verified working on the user's Arc. Needs `NSAppleEventsUsageDescription`.
- **Zen workspace:** open `ext+container:name=<container>&url=<url>` (percent-encoded) with Zen.
  Requires the "Open external links in a container" add-on and
  `zen.workspaces.force-container-workspace = true` (found in Zen source: makes a container tab
  switch to the workspace owning that container; default false).
- **Chromium profile:** `NSWorkspace.openApplication` with
  `createsNewApplicationInstance = true`, args `--profile-directory=<dir>` + URLs.
- **Plain browser:** `NSWorkspace.open(urls, withApplicationAt:)`.
- Any failure → plain open in that browser (anti-goal: never lose a link).

### Source app detection

Install a `kAEGetURL` handler via `NSAppleEventManager` in `applicationWillFinishLaunching`
(not `application(_:open:)`, which loses the sender). Read the sender PID
(`keySenderPIDAttr`) → `NSRunningApplication` → bundle id. If unknown, source = nil.
Also handle `NSUserActivity` browsing-web continuation like Browserino does.

### Rules

- Fields: name (optional), URL pattern (host glob like `*.atlassian.net`, or regex — toggle),
  source apps (set of bundle ids, optional), target. Empty URL pattern + source app = "anything
  from this app".
- Evaluated top to bottom on the **cleaned** URL; first match opens directly.
- Holding **Option** while clicking a link forces the picker (bypass rules).
- A rule whose target no longer exists falls through to the picker.

### Learning

- Store per (host, sourceBundleId?) a list of recent choices (target id + timestamp).
- Ranking in the picker: frecency score per target for this host (with source app match
  weighted higher), then global frecency, then discovery order. Top item is preselected.
- Suggestion: same target chosen for the same host 3 times in a row with no rule → inline
  banner in the picker on the next open: "Always open <host> in <target>?" (Enter on banner / ⌘S
  creates a host rule; ✕ dismisses for that host permanently).

### Picker UI

- Non-activating panel at the mouse cursor (like Browserino's `BrowserinoWindow`: NSPanel,
  shielding level, all spaces, closes on resign key).
- Top: cleaned URL (host bold + path dimmed, truncated); ⌘C copies it.
- Search field focused immediately; typing filters (fuzzy subsequence on "browser · profile").
- Rows: browser icon + target name; profile rows show browser icon small + emoji (Zen).
- Keys: ↑/↓ select, Enter open, 1–9 open nth row, Esc cancel.
- Suggestion banner (learning) above the list when applicable.

### Link cleaning

- Unwrap (repeat until stable, max 5): Outlook SafeLinks (`*.safelinks.protection.outlook.com`
  `?url=`), Teams SafeLinks (`statics.teams.cdn.office.net/evergreen-assets/safelinks/…?url=`),
  Google (`google.*/url?q=` or `url=`), Slack (`slack-redir.net/link?url=`),
  Facebook (`l.facebook.com/l.php?u=`), Yandex/VK/Telegram away-links if trivially parseable.
- Strip params: `utm_*`, `fbclid`, `gclid`, `yclid`, `mc_eid`, `mc_cid`, `_hsenc`, `_hsmi`.
- Global toggle in settings (default on). The original URL is never needed after cleaning.

### Settings window (SwiftUI)

- **General:** set as default browser (`NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)`
  for http/https), launch at login (`SMAppService.mainApp`), link cleaning toggle, menu bar icon.
- **Targets:** grouped by browser, show/hide each target, rescan, hints (Zen setup checklist:
  container per workspace, add-on, pref; Chrome FDA).
- **Rules:** list, add/edit/delete, reorder, test field ("paste a URL → which rule matches").

### Storage

- JSON files in `~/Library/Application Support/BrowserZero/`: `config.json` (rules, hidden targets,
  settings), `targets-cache.json`, `history.json`. Keep the config schema clean enough to become
  TOML later.

## Left to the builder

- Module/file layout, fuzzy matching algorithm, frecency formula details, visual styling
  (keep it close to native macOS, Browserino-like compact panel), app icon (SF Symbol based is
  fine), exact test framework.
- Migration from Browserino settings: nice-to-have, not required.

## Verification

- Unit tests for: URL cleaning (fixtures for each wrapper), rule matching, mozLz4 decode +
  Zen/Arc/Chromium parsers (sanitized fixture files), ranking/suggestion logic.
- Manual: build, install to `/Applications`, set as default, click links from Telegram and
  Teams; Arc space opening verified live.

## Calls made after builder review (mine, not the user's)

- **Digits vs search:** bare `1–9` open a row only while the search field is empty; `⌘1–9` always.
- **Target identity:** `browserBundleId + kind + name` (Arc by space title). Renaming a space
  breaks rules/history pointing at it → falls through to the picker, as specified.
- **Zen add-on detection:** before using `ext+container:`, check the Zen profile's
  `extensions.json` for the add-on and `prefs.js` for `force-container-workspace`. If either is
  missing → open plainly in Zen and show the setup checklist in Targets.
- **Source app:** normalize helper processes to their parent app (walk up to the first
  `NSRunningApplication` with a regular activation policy / bundle containing the helper).
  Verify manually with Teams and Outlook.
- **Host glob:** `*.example.com` matches `example.com` and any subdomain.
- **Option to force picker:** read `NSEvent.modifierFlags` when the URL event arrives. If
  unreliable, fall back to a menu bar toggle "Show picker for next link".
