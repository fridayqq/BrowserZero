# Spacelink MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS default-browser app that opens each link in a browser *or a space/profile inside it*, via rules (URL + source app), learning, a type-to-filter picker, and link cleaning.

**Architecture:** SwiftPM package. `SpacelinkCore` = pure, unit-tested logic (models, cleaning, rules, ranking, discovery parsers, storage, script/URL builders). `Spacelink` = executable with AppKit/SwiftUI glue (Apple Event handler, opener, picker panel, settings). `scripts/build-app.sh` assembles and ad-hoc signs `build/Spacelink.app`.

**Tech Stack:** Swift 6 toolchain (language mode 5 for the app target to avoid strict-concurrency churn), SwiftUI + AppKit, Compression, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-31-spacelink-design.md` — read it before your task.

## Global Constraints

- No Xcode. Every build/test command is prefixed with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). XCTest does not build here.
- Do not use `#Preview`. Do not use regex literals (`/…/`); use `NSRegularExpression` or `Regex(String)`.
- Platform: `.macOS(.v14)`. Bundle id `dev.fridayqq.Spacelink`. App is `LSUIElement` (menu bar only).
- Info.plist must contain `NSAppleEventsUsageDescription`, URL types `http`, `https`, and `CFBundleDocumentTypes` for `public.html` (copy shape from `~/code/Browserino/Browserino/Info.plist`).
- Never lose a link: every open failure falls back to a plain open in the target's browser.
- Reference implementation for discovery/opening (verified on this machine): `~/code/Browserino/Browserino/Models/BrowserProfile.swift`. Port logic from it; don't copy its UI.
- Commit after every task; author `-c user.email=112469247+fridayqq@users.noreply.github.com -c user.name="fridayqq"`.

## Review Focus

1. URL containing `"`, `\`, spaces or Cyrillic going into Arc AppleScript → must stay a valid script and open the exact URL (test in Task 5, `ScriptBuilder`).
2. Target URL containing `&`, `=`, `+`, `#` going through Zen `ext+container:` → the `url` query value decodes back to the exact original (test in Task 5, `ZenLink`).
3. Wrapper link with missing/garbage `url` param (e.g. `…safelinks…/?data=x`) → returned unchanged, no crash (test in Task 2).
4. Rule with invalid regex → skipped, other rules still evaluated (test in Task 3).
5. Corrupt or missing `config.json` / `history.json` / `targets-cache.json` → defaults load, app keeps working (test in Task 6).

---

## File Structure

```
Package.swift
scripts/build-app.sh
Support/Info.plist
Sources/SpacelinkCore/
  Target.swift          Target, Profile, ProfileKind, BrowserApp
  LinkCleaner.swift
  Rule.swift            Rule, RuleMatcher
  Fuzzy.swift
  History.swift         Choice, History (ranking + suggestion)
  ScriptBuilder.swift   Arc AppleScript, Zen ext+container URL, Chromium args
  Discovery/MozLz4.swift
  Discovery/ArcDiscovery.swift
  Discovery/ZenDiscovery.swift
  Discovery/ChromiumDiscovery.swift
  Discovery/TargetDiscovery.swift
  Store.swift           Config, Store (JSON persistence)
Sources/Spacelink/
  main.swift, AppDelegate.swift, AppState.swift
  Browsers.swift, SourceApp.swift, Opener.swift, Router.swift
  Picker/PickerPanel.swift, Picker/PickerModel.swift, Picker/PickerView.swift
  Settings/SettingsWindow.swift, Settings/GeneralTab.swift, Settings/TargetsTab.swift, Settings/RulesTab.swift
Tests/SpacelinkCoreTests/*.swift (+ Fixtures/ via `resources: [.copy("Fixtures")]`)
```

---

### Task 1: Package scaffold, build script, core models

**Files:**
- Create: `Package.swift`, `scripts/build-app.sh`, `Support/Info.plist`, `.gitignore` (`.build/`, `build/`)
- Create: `Sources/SpacelinkCore/Target.swift`, `Sources/Spacelink/main.swift`, `Sources/Spacelink/AppDelegate.swift`
- Test: `Tests/SpacelinkCoreTests/TargetTests.swift`

**Interfaces:**
- Produces:
  - `public enum ProfileKind: String, Codable, Sendable { case arcSpace, zenWorkspace, chromiumProfile }`
  - `public struct Profile: Codable, Hashable, Sendable { kind: ProfileKind; name: String; value: String; icon: String? }` — `value`: Arc space title / Zen container name / Chromium profile dir; empty = not selectable.
  - `public struct BrowserApp: Codable, Hashable, Sendable { bundleId: String; path: String; name: String }`
  - `public struct Target: Codable, Hashable, Identifiable, Sendable { browser: BrowserApp; profile: Profile? }` with
    `id: String` = `"\(browser.bundleId)|\(profile?.kind.rawValue ?? "browser")|\(profile?.name ?? "")"`,
    `isSelectable: Bool` (profile == nil || !profile.value.isEmpty),
    `displayName: String` = `"Arc"` or `"Arc · Dev"` (separator `" · "`).
  - All public structs get public memberwise inits.

- [ ] **Step 1: Write `Package.swift`** — tools 6.0; products: executable `Spacelink`; targets `SpacelinkCore` (library), `Spacelink` (executable, depends on core, `swiftSettings: [.swiftLanguageMode(.v5)]`), test target `SpacelinkCoreTests` with `resources: [.copy("Fixtures")]` (create `Tests/SpacelinkCoreTests/Fixtures/.keep`).
- [ ] **Step 2: Write failing tests** in `TargetTests.swift`:
  - `targetIdForPlainBrowser`: `Target(browser: arc, profile: nil).id == "company.thebrowser.Browser|browser|"`
  - `targetIdForProfile`: with `Profile(kind: .arcSpace, name: "Dev", value: "Dev", icon: nil)` → `"company.thebrowser.Browser|arcSpace|Dev"`, `displayName == "Arc · Dev"`
  - `zenWithoutContainerNotSelectable`: `Profile(kind: .zenWorkspace, name: "SL", value: "", icon: "🏢")` → `isSelectable == false`
- [ ] **Step 3: Run** `SDKROOT=… swift test` → FAIL (types missing).
- [ ] **Step 4: Implement `Target.swift`.**
- [ ] **Step 5: Minimal app:** `main.swift` creates `NSApplication`, sets `AppDelegate`, `.accessory` policy, runs. `AppDelegate` adds a status item (SF Symbol `"arrow.triangle.branch"`) with menu: "Settings…" (no-op for now), "Quit".
- [ ] **Step 6: `scripts/build-app.sh`** — `swift build -c release` with SDKROOT; create `build/Spacelink.app/Contents/{MacOS,Resources}`; copy `.build/release/Spacelink`; copy `Support/Info.plist` (it already contains `CFBundleIdentifier`, `CFBundleExecutable=Spacelink`, `CFBundleName`, `CFBundlePackageType=APPL`, `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=1`, `LSMinimumSystemVersion=14.0`, `LSUIElement=true`, `NSAppleEventsUsageDescription`, URL types, document types); `codesign --force --deep --sign - build/Spacelink.app`. `set -euo pipefail`.
- [ ] **Step 7: Verify:** `swift test` PASS (3 tests); `scripts/build-app.sh` prints no errors; `codesign -v build/Spacelink.app` exits 0; `plutil -lint Support/Info.plist` OK.
- [ ] **Step 8: Commit** `feat: scaffold Spacelink package and core models`.

---

### Task 2: LinkCleaner

**Files:** Create `Sources/SpacelinkCore/LinkCleaner.swift`; Test `Tests/SpacelinkCoreTests/LinkCleanerTests.swift`

**Interfaces:**
- Produces: `public enum LinkCleaner { public static func clean(_ url: URL) -> URL }`

Unwrap rules (repeat until unchanged, max 5 rounds), extracting the named query param and parsing it as an absolute `http(s)` URL; if absent/invalid, stop and keep current URL:
- host ends with `.safelinks.protection.outlook.com` → `url`
- host `statics.teams.cdn.office.net`, path contains `/safelinks/` → `url`
- host is `google.<tld>` or `www.google.<tld>`, path `/url` → `q`, else `url`
- host `slack-redir.net`, path `/link` → `url`
- host `l.facebook.com` or `lm.facebook.com`, path `/l.php` → `u`
- host `away.vk.com`, path `/away.php` → `to`

Then strip params: names starting with `utm_`, and `fbclid`, `gclid`, `yclid`, `mc_eid`, `mc_cid`, `_hsenc`, `_hsmi`. Remove `?` entirely if no params remain. Keep fragment.

- [ ] **Step 1: Failing tests:**
  - `unwrapsOutlookSafeLinks`: `https://eur02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fdev.atlassian.net%2Fbrowse%2FDATA-1&data=05` → `https://dev.atlassian.net/browse/DATA-1`
  - `unwrapsTeamsSafeLinks`: `https://statics.teams.cdn.office.net/evergreen-assets/safelinks/1/atp-safelinks.html?url=https%3A%2F%2Fexample.com%2Fa&locale=en` → `https://example.com/a`
  - `unwrapsGoogle`: `https://www.google.com/url?q=https://example.com/x&sa=D` → `https://example.com/x`
  - `unwrapsNested`: SafeLinks wrapping a google `/url?q=` link → inner target
  - `stripsTracking`: `https://example.com/p?utm_source=a&id=7&fbclid=z#top` → `https://example.com/p?id=7#top`
  - `removesEmptyQuery`: `https://example.com/p?utm_medium=x` → `https://example.com/p`
  - `brokenWrapperUnchanged` (Review Focus 3): `https://eur02.safelinks.protection.outlook.com/?data=x` → unchanged; `…?url=not%20a%20url` → unchanged
  - `plainLinkUnchanged`: `https://github.com/a/b?tab=readme` → unchanged
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** with `URLComponents`. **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: link cleaning`.

---

### Task 3: Rules

**Files:** Create `Sources/SpacelinkCore/Rule.swift`; Test `Tests/SpacelinkCoreTests/RuleTests.swift`

**Interfaces:**
- Produces:
  - `public struct Rule: Codable, Hashable, Identifiable, Sendable { id: UUID; name: String; pattern: String; isRegex: Bool; sourceApps: [String]; targetId: String }`
  - `public enum RuleMatcher { static func hostMatches(glob: String, host: String) -> Bool; static func matches(_ rule: Rule, url: URL, sourceApp: String?) -> Bool; static func firstMatch(url: URL, sourceApp: String?, rules: [Rule]) -> Rule? }`

Semantics: glob is matched against the host only, case-insensitive; `*.x.com` matches `x.com` and any subdomain; `*` matches anything; otherwise exact host. Regex (`isRegex`) is matched case-insensitive against the full `absoluteString`; invalid regex → rule never matches. Empty `pattern` = URL condition passes. Non-empty `sourceApps` requires `sourceApp` ∈ list. A rule with empty pattern AND empty sourceApps never matches.

- [ ] **Step 1: Failing tests:** `globMatchesSubdomainAndApex` (`*.atlassian.net` vs `dev.atlassian.net` true, `atlassian.net` true, `evilatlassian.net` false); `exactHost`; `regexOnFullURL` (`jira.*/browse/` matches); `sourceAppOnly` (pattern "", sourceApps `["com.microsoft.teams2"]` matches any URL from Teams, not from nil); `bothConditions`; `emptyRuleNeverMatches`; `invalidRegexSkipped` (Review Focus 4: rules `[bad "(", good]` → `firstMatch` returns `good`); `firstMatchWins` (order).
- [ ] **Step 2–4:** run FAIL → implement → run PASS.
- [ ] **Step 5: Commit** `feat: rule matching`.

---

### Task 4: Fuzzy filter and History (ranking + suggestion)

**Files:** Create `Sources/SpacelinkCore/Fuzzy.swift`, `Sources/SpacelinkCore/History.swift`; Tests `FuzzyTests.swift`, `HistoryTests.swift`

**Interfaces:**
- Produces:
  - `public enum Fuzzy { static func score(query: String, candidate: String) -> Int? }` — case- and diacritic-insensitive subsequence match; `nil` = no match; empty query → `0`. Higher is better: +10 per char at a word start (start, or after space/`·`/`-`), +5 for consecutive chars, +20 if candidate has query as prefix of any word.
  - `public struct Choice: Codable, Hashable, Sendable { host: String; source: String?; targetId: String; date: Date }`
  - `public struct History: Codable, Sendable { public var choices: [Choice]; public init(choices: [Choice] = []); mutating func record(host: String, source: String?, targetId: String, at: Date); func rank(_ targets: [Target], host: String, source: String?, now: Date) -> [Target]; func suggestion(host: String, rules: [Rule], dismissed: Set<String>) -> String? }`

Ranking: score(target) = Σ over choices with that targetId of `weight × decay`, where weight = 4 if host and source both equal, 3 if host equal, 1 otherwise; decay = `0.5^(ageDays/14)`. Stable sort descending; ties keep input order. `record` keeps at most 2000 newest choices.
Suggestion: returns targetId if the last 3 choices for `host` (most recent first, any source) all have the same targetId, `host` ∉ `dismissed`, and no rule is a non-regex rule whose `hostMatches(glob: pattern, host:)` is true; else nil.

- [ ] **Step 1: Failing tests:**
  - Fuzzy: `"de"` matches `"Arc · Dev"`; `"xz"` vs `"Arc · Dev"` → nil; `score("dev", "Dia · Dev") > score("dev", "Data Entry View")`; `"zen"` matches `"Zen · Personal"` case-insensitively; empty query → 0.
  - History: `rankPrefersSameHost` (3 choices of Dev on `jira.x` → Dev first for host `jira.x`); `rankPrefersSourceMatch`; `rankDecaysOld` (old 60-day choices lose to 1 fresh one for a different target on same host — compute: 5 × 3 × 0.5^(60/14) ≈ 0.77 < 3); `rankStableWithoutHistory`; `suggestionAfterThree`; `noSuggestionIfMixed`; `noSuggestionIfRuleExists`; `noSuggestionIfDismissed`; `recordCapsAt2000`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat: fuzzy filter and learning`.

---

### Task 5: Discovery parsers and script/URL builders

**Files:**
- Create: `Sources/SpacelinkCore/Discovery/{MozLz4,ArcDiscovery,ZenDiscovery,ChromiumDiscovery}.swift`, `Sources/SpacelinkCore/ScriptBuilder.swift`
- Create fixtures in `Tests/SpacelinkCoreTests/Fixtures/`: `arc-sidebar.json`, `zen-sessions.json` (plain JSON; test compresses it), `zen-containers.json`, `zen-profiles.ini`, `zen-extensions.json`, `zen-prefs.js`, `chrome-local-state.json` — small hand-written files mirroring the shapes in the spec (Arc: `{"sidebar":{"containers":[{"global":{}}, {"spaces":["id1",{"id":"id1","title":"Personal"},"id2",{"id":"id2","title":"Dev"},{"id":"id3","title":"Dev"}]}]}}`; Zen spaces with `containerTabId` 0 and 2; containers ids 1–4 without names plus id 6 `"name":"Clients"`).
- Test: `DiscoveryTests.swift`, `ScriptBuilderTests.swift`

**Interfaces:**
- Produces:
  - `public enum MozLz4 { static func decode(_ data: Data) -> Data?; static func encode(_ data: Data) -> Data }` (encode for tests; `COMPRESSION_LZ4_RAW`)
  - `public enum ArcDiscovery { static let bundleId = "company.thebrowser.Browser"; static func spaces(sidebarJSON: Data) -> [Profile]? }` — dedupe by title, keep order, skip empty titles; `nil` if JSON shape invalid.
  - `public enum ZenDiscovery { static let bundleId = "app.zen-browser.zen"; static let addonName = "Open external links in a container"; static func profilePath(iniText: String) -> String?; static func workspaces(sessionsJSON: Data, containersJSON: Data?) -> [Profile]?; static func isAddonInstalled(extensionsJSON: Data) -> Bool; static func isForceContainerEnabled(prefsJS: String) -> Bool }` — profilePath: `[Install…] Default=` first, else section with `Default=1` → its `Path`. Container names: `name`, else ids 1–4 → Personal/Work/Banking/Shopping. Only `public: true` identities. Addon: any `addons[]` whose `defaultLocale.name` contains `addonName` and `active == true`. Pref: line `user_pref("zen.workspaces.force-container-workspace", true);`.
  - `public enum ChromiumDiscovery { static let dataDirs: [String: String]; static func profiles(localStateJSON: Data) -> [Profile]? }` — `dataDirs` copied from the Browserino fork (`chromiumDirs`). `info_cache` + `profiles_order`; return `[]` if ≤1 profile.
  - `public enum ScriptBuilder { static func arcScript(space: String, urls: [URL]) -> String; static func zenContainerURL(container: String, url: URL) -> URL; static func chromiumArguments(profileDir: String, urls: [URL]) -> [String] }` — Arc script exactly as in the spec (ensure window → front window → `tell space "<t>"` → `focus` + one `make new tab with properties {URL:"…"}` per URL → `activate`), escaping `\` then `"`. Zen: `ext+container:name=<enc>&url=<enc>` where enc = percent-encoding with `.alphanumerics` + `-._~` allowed only. Chromium: `["--profile-directory=<dir>"] + urls.map(\.absoluteString)`.

- [ ] **Step 1: Failing tests:**
  - `mozLz4RoundTrip` (encode→decode equals); `mozLz4RejectsBadMagic` → nil
  - `arcSpacesDeduped` → names `["Personal","Dev"]`, kinds `.arcSpace`, value == name
  - `zenProfilePathFromInstall` → `"Profiles/4ata6ldq.Default (release)"`
  - `zenWorkspacesWithContainers` → workspace with containerTabId 2 has value `"Work"`, with 0 has value `""`, icons preserved
  - `zenAddonDetected` / `zenPrefDetected` (true and false fixtures/strings)
  - `chromiumProfilesOrdered` → `[("Person 1","Default"),("A","Profile 1")]`; `chromiumSingleProfileEmpty` → `[]`
  - `arcScriptEscapes` (Review Focus 1): URL `https://e.com/?q="x"\y` and space `My "Work"` → script contains `tell space "My \"Work\""` and `{URL:"https://e.com/?q=%22x%22%5Cy"}` (URL as `absoluteString`; additionally assert compiling via `NSAppleScript(source:)!.compileAndReturnError` succeeds)
  - `zenURLRoundTrip` (Review Focus 2): url `https://e.com/a?b=1&c=2+3#frag` → parse result with `URLComponents(string: s.replacingOccurrences(of: "ext+container:", with: "x:?"))` → `url` item equals original absoluteString, `name` equals container
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat: discovery parsers and open builders`.

---

### Task 6: TargetDiscovery and Store

**Files:** Create `Sources/SpacelinkCore/Discovery/TargetDiscovery.swift`, `Sources/SpacelinkCore/Store.swift`; Tests `TargetDiscoveryTests.swift`, `StoreTests.swift`

**Interfaces:**
- Consumes: Task 1 models, Task 5 parsers, Task 3 `Rule`, Task 4 `History`.
- Produces:
  - `public struct ZenSetup: Codable, Hashable, Sendable { addonInstalled: Bool; forceContainerEnabled: Bool; profileFound: Bool }`
  - `public struct TargetDiscovery { public init(appSupport: URL); func discover(browsers: [BrowserApp], previous: [Target]) -> [Target]; func zenSetup() -> ZenSetup; func zenProfileDirectory() -> URL? }` — per browser: one plain `Target` + one per profile (including non-selectable ones). If a browser's source exists but can't be read/parsed (`nil` from parser or read error), reuse `previous` profile targets for that bundleId. Paths: Arc `Arc/StorableSidebar.json`; Zen `zen/profiles.ini` → dir → `zen-sessions.jsonlz4`, `containers.json`, `extensions.json`, `prefs.js`; Chromium `<dataDirs[id]>/Local State`.
  - `public struct Config: Codable, Equatable, Sendable { rules: [Rule] = []; hiddenTargets: Set<String> = []; hiddenBrowsers: Set<String> = []; cleanLinks: Bool = true; dismissedSuggestions: Set<String> = [] }` — decoding must tolerate missing keys (custom `init(from:)` with `decodeIfPresent`).
  - `public final class Store { public init(directory: URL); func loadConfig() -> Config; func save(_: Config); func loadHistory() -> History; func save(_: History); func loadTargets() -> [Target]; func saveTargets(_: [Target]) }` — files `config.json`, `history.json`, `targets-cache.json`; creates directory; atomic writes; missing/corrupt file → default value. Default directory used by the app: `~/Library/Application Support/Spacelink/`.

- [ ] **Step 1: Failing tests** (temp dir as fake App Support, copy Task 5 fixtures into the right paths, mozLz4-encode sessions):
  - `discoversArcZenChromium` → contains ids `company.thebrowser.Browser|arcSpace|Dev`, `app.zen-browser.zen|zenWorkspace|SL` (not selectable), plain targets for each browser
  - `unreadableKeepsPrevious` → Chromium `Local State` replaced with garbage; previous contains `com.google.Chrome|chromiumProfile|A` → still present
  - `missingSourceGivesPlainOnly` → browser with no data dir → only plain target
  - `zenSetupFlags`
  - `storeRoundTrip` (config, history, targets)
  - `corruptFilesGiveDefaults` (Review Focus 5): write `"{oops"` to all three → defaults, then `save` works
  - `configToleratesMissingKeys`: `{"rules":[]}` decodes with `cleanLinks == true`
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `feat: target discovery and persistence`.

---

### Task 7: App core — state, source app, opener, router, URL events

**Files:** Create `Sources/Spacelink/{AppState,Browsers,SourceApp,Opener,Router}.swift`; Modify `AppDelegate.swift`

**Interfaces:**
- Consumes: all of SpacelinkCore.
- Produces:
  - `final class AppState: ObservableObject` (main actor) — `@Published config: Config`, `@Published targets: [Target]`, `@Published history: History`, `@Published zenSetup: ZenSetup`; `let store: Store`; `func refreshTargets()` (background discovery → main, saves cache); `func visibleTargets() -> [Target]` (selectable, not in hiddenTargets, browser not in hiddenBrowsers); `func saveConfig()`; `func record(host:source:targetId:)`. Loads cached targets at init, then refreshes.
  - `enum Browsers { static func installed() -> [BrowserApp] }` — `NSWorkspace.urlsForApplications(toOpen: https:)`, excluding own bundle id and `com.googlecode.iterm2`, `com.openai.chat`, `com.openai.codex`, `com.apple.Terminal`; dedupe by bundle id (prefer `/Applications`); always include Safari if found.
  - `enum SourceApp { static func bundleId(forPID: pid_t) -> String? }` — `NSRunningApplication(processIdentifier:)`; if its activationPolicy isn't `.regular`, walk up parent PIDs (`sysctl` `KERN_PROC_PID` → `kp_eproc.e_ppid`) until a regular app or pid ≤ 1; if still none, try bundle path containment (helper inside another `.app`).
  - `enum Opener { static func open(_ urls: [URL], target: Target, zenSetup: ZenSetup) }` — Arc space: `ScriptBuilder.arcScript` on serial background queue via `NSAppleScript`; error → plain. Zen workspace: if `zenSetup.addonInstalled && forceContainerEnabled` → open `zenContainerURL` per URL with Zen, else plain. Chromium: `openApplication` with `createsNewApplicationInstance = true` + `chromiumArguments`. Plain: `NSWorkspace.open(urls, withApplicationAt:)`. Port from fork.
  - `final class Router` — `init(state: AppState, showPicker: @escaping (URL, String?) -> Void)`; `func handle(_ url: URL, sourceApp: String?, forcePicker: Bool)`: clean if `config.cleanLinks` → if `!forcePicker`, `RuleMatcher.firstMatch` and its target exists in `state.targets` → `Opener.open` + `record` → else `showPicker(cleaned, sourceApp)`.
  - AppDelegate: in `applicationWillFinishLaunching`, `NSAppleEventManager.shared().setEventHandler(_, andSelector:, forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))`; handler reads `paramDescriptor(forKeyword: keyDirectObject)?.stringValue`, sender PID from `event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value`, `forcePicker = NSEvent.modifierFlags.contains(.option)`. Also `application(_:open:)` for file URLs (html files) → router with source nil. For this task, `showPicker` temporarily opens in the first visible plain target.

- [ ] **Step 1: Build** `SDKROOT=… swift build` → no errors; `swift test` still PASS.
- [ ] **Step 2: Manual check:** `scripts/build-app.sh`, then `open -a build/Spacelink.app "https://example.com/?utm_source=x"` → page opens in first browser without `utm_source`. Temporarily add a rule in `~/Library/Application Support/Spacelink/config.json` (`pattern "example.com"`, target `company.thebrowser.Browser|arcSpace|A`), relaunch, repeat → opens in Arc space A (approve Automation prompt). Remove the rule.
- [ ] **Step 3: Commit** `feat: URL routing, opener and source app detection`.

---

### Task 8: Picker panel

**Files:** Create `Sources/Spacelink/Picker/{PickerPanel,PickerModel,PickerView}.swift`; Modify `AppDelegate.swift` (wire `showPicker`)

**Interfaces:**
- Consumes: `AppState`, `Opener`, `History.rank`, `History.suggestion`, `Fuzzy.score`.
- Produces:
  - `final class PickerModel: ObservableObject` — `init(url: URL, source: String?, state: AppState, close: @escaping () -> Void)`; `@Published query`, `@Published selection: Int`; `var rows: [Target]` = ranked visible targets, then filtered/sorted by `Fuzzy.score(query, displayName)` when query non-empty (ties keep rank order); `var suggestion: Target?`; `func open(_ index: Int)` (opens, records history, closes); `func acceptSuggestion()` (appends `Rule(pattern: host, isRegex: false, sourceApps: [], targetId:)`, saves, opens); `func dismissSuggestion()` (adds host to `dismissedSuggestions`).
  - `final class PickerPanel: NSPanel` — non-activating, titled+fullSizeContentView, transparent titlebar, no buttons, level `CGShieldingWindowLevel()`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, positioned so the top is near the cursor and clamped 20pt inside the screen's visible frame (see fork `BrowserinoApp.swift`), width 300, height fits rows up to 420; closes on resign key; `canBecomeKey = true`.
  - `PickerView` — top: host (semibold) + path (secondary, middle-truncated), click/⌘C copies URL; search `TextField` focused on appear; optional suggestion banner "Always open <host> in <target>?" with buttons Always (⌘S) / ✕; list rows: browser icon (`NSWorkspace.icon(forFile:)`, 20pt; 14pt + Zen emoji for profiles), `displayName`, trailing index hint 1–9; selected row highlighted.
  - Keys: ↑/↓ move selection (clamped), Enter opens selected (no-op if no rows), Esc closes, bare 1–9 open row when query empty, ⌘1–9 always. Typing resets selection to 0.

- [ ] **Step 1: Build** passes; tests still pass.
- [ ] **Step 2: Manual check:** build app, `open -a build/Spacelink.app https://github.com` → panel at cursor; type `de` → only Dev rows; Enter opens; Esc closes; `1` opens first row. Choose the same target 3× for github.com → 4th time banner appears; ⌘S creates rule; 5th time opens without picker. Hold Option while running → picker shows despite rule.
- [ ] **Step 3: Commit** `feat: picker panel`.

---

### Task 9: Settings window

**Files:** Create `Sources/Spacelink/Settings/{SettingsWindow,GeneralTab,TargetsTab,RulesTab}.swift`; Modify `AppDelegate.swift` (menu "Settings…" opens window; reopen app opens it too)

**Interfaces:**
- Consumes: `AppState`, `RuleMatcher`, `LinkCleaner`.
- Produces: `final class SettingsWindowController` with `func show()` (single NSWindow 720×520, hosting `TabView`).
  - **General:** "Set as default browser" button (`NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")` and `"https"`) with current status text; "Launch at login" toggle (`SMAppService.mainApp` register/unregister); "Clean links" toggle bound to `config.cleanLinks`.
  - **Targets:** "Rescan" button; sections per browser (icon + name, eye toggle → `hiddenBrowsers`); rows per profile target: emoji, name, kind label, eye toggle → `hiddenTargets`; non-selectable Zen rows show orange "needs container". Zen checklist when Zen installed: ✓/✗ add-on installed, ✓/✗ `force-container-workspace`, ✓/✗ every workspace has a container. Hint text for Chrome Full Disk Access when Chrome is installed but has no profile targets.
  - **Rules:** list (drag to reorder, delete); add/edit sheet: name, pattern + "Regex" toggle, source apps (pick `.app` via file importer → bundle id, removable chips), target `Picker` over `state.targets.filter(\.isSelectable)` by `displayName`; test field: paste URL + optional source bundle id → shows cleaned URL and which rule matches (or "picker").

- [ ] **Step 1: Build** passes; tests pass.
- [ ] **Step 2: Manual check:** open Settings from menu; Rescan shows Arc spaces, Zen workspaces (needs container), Dia profiles; hide Arc · SL → it disappears from picker; create rule "from Telegram (`ru.keepcoder.Telegram`) → Arc · Personal", test field shows match; Set as default works (macOS confirmation dialog).
- [ ] **Step 3: Commit** `feat: settings window`.

---

### Task 10: Install and end-to-end check

**Files:** Create `README.md` (what it is, build: `scripts/build-app.sh`, install: copy to `/Applications`, Zen setup steps, Chrome FDA note).

- [ ] **Step 1:** `swift test` all PASS; `scripts/build-app.sh` OK.
- [ ] **Step 2:** Copy `build/Spacelink.app` to `/Applications`, `lsregister -f`, launch. Do **not** change the default browser or remove Browserino — leave switching to the user.
- [ ] **Step 3:** `open -a /Applications/Spacelink.app <url>` checks: SafeLinks URL gets unwrapped; Arc space opens; Dia profile opens.
- [ ] **Step 4: Commit** `docs: README`.
