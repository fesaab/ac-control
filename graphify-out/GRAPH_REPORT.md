# Graph Report - ac-control  (2026-10-24)

## Corpus Check
- 22 files · ~9,150 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 303 nodes · 616 edges · 22 communities (16 shown, 6 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 64 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- AppModel
- ACProfile
- .refresh
- ACError
- JSONValue
- FixtureTransport
- ACControlCore
- AppDelegate
- AC Control
- Package.swift
- build-app.sh
- THIRD_PARTY_NOTICES.md
- AC Control
- AccountDevice
- FanSpeedOption
- fanProfile
- .loadDemo
- AccountDevicesView
- .applicationDidFinishLaunching
- Bool
- QuickControlView
- test.sh

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 56 edges
2. `JSONValue` - 33 edges
3. `ACProfile` - 21 edges
4. `ACSnapshot` - 21 edges
5. `ACError` - 21 edges
6. `AccountDevice` - 19 edges
7. `AppDelegate` - 17 edges
8. `FixtureTransport` - 17 edges
9. `ThinQClient` - 14 edges
10. `fanProfile()` - 14 edges

## Surprising Connections (you probably didn't know these)
- `fanProfile()` --calls--> `ACProfile`  [EXTRACTED]
  Tests/ACControlCoreTests/FanSpeedTests.swift → Sources/ACControlCore/Device.swift
- `fanSnapshot()` --calls--> `ACSnapshot`  [EXTRACTED]
  Tests/ACControlCoreTests/FanSpeedTests.swift → Sources/ACControlCore/Device.swift
- `FixtureTransport` --implements--> `HTTPTransport`  [EXTRACTED]
  Tests/ACControlCoreTests/ThinQClientTests.swift → Sources/ACControlCore/ThinQClient.swift
- `.body` --calls--> `AccountDevicesView`  [INFERRED]
  Sources/ACControl/Views.swift → Sources/ACControl/AccountDevicesView.swift
- `AppDelegate` --calls--> `AppModel`  [INFERRED]
  Sources/ACControl/main.swift → Sources/ACControl/AppModel.swift

## Import Cycles
- None detected.

## Communities (22 total, 6 thin omitted)

### Community 0 - "AppModel"
Cohesion: 0.11
Nodes (18): Never, ObservableObject, AppModel, .barHelp, .barSymbol, .barTitle, .canControl, .canSetFanSpeed (+10 more)

### Community 1 - "ACProfile"
Cohesion: 0.10
Nodes (22): Date, Equatable, ACProfile, .canSwitchPower, .power, ACSnapshot, DeviceSelection, needsSelection (+14 more)

### Community 2 - ".refresh"
Cohesion: 0.10
Nodes (18): NSObject, Sendable, configuration, DotEnv, LGConfiguration, String, HTTPTransport, NoRedirects (+10 more)

### Community 3 - "ACError"
Cohesion: 0.14
Nodes (13): Error, LocalizedError, ACError, api, .errorDescription, http, invalidResponse, missingToken (+5 more)

### Community 4 - "JSONValue"
Cohesion: 0.11
Nodes (15): Codable, Decoder, Encoder, JSONValue, array, bool, null, number (+7 more)

### Community 5 - "FixtureTransport"
Cohesion: 0.25
Nodes (8): FixtureTransport, Bool, Data, HTTPURLResponse, Int, String, URLRequest, ThinQClientTests

### Community 6 - "ACControlCore"
Cohesion: 0.14
Nodes (12): ACControlCore, AppKit, Combine, Foundation, ServiceManagement, Part, symbol, text (+4 more)

### Community 7 - "AppDelegate"
Cohesion: 0.14
Nodes (11): AnyCancellable, Notification, NSApplication, NSApplicationDelegate, NSObjectProtocol, NSPopoverDelegate, NSStatusItem, NSWindow (+3 more)

### Community 8 - "AC Control"
Cohesion: 0.18
Nodes (10): AC Control, Atualização e confirmação, Comportamento, Estrutura e testes, Executar localmente, Fontes técnicas, Prévias nativas, Seleção do dispositivo (+2 more)

### Community 12 - "AC Control"
Cohesion: 0.33
Nodes (5): AC Control, Build and verification, Configuration, graphify, Real accounts and appliances

### Community 13 - "AccountDevice"
Cohesion: 0.18
Nodes (8): .selectedDevice, AccountDevice, .isControllable, .kindDescription, .symbol, Self, DeviceSelectionTests, String

### Community 14 - "FanSpeedOption"
Cohesion: 0.23
Nodes (9): Identifiable, .currentFanOptionID, .fanSpeedControl, FanSpeedControl, FanSpeedOption, .id, .title, Bool (+1 more)

### Community 15 - "fanProfile"
Cohesion: 0.26
Nodes (4): fanProfile(), fanSnapshot(), FanSpeedTests, String

### Community 16 - ".loadDemo"
Cohesion: 0.33
Nodes (4): Double, Error, String, .body

### Community 17 - "AccountDevicesView"
Cohesion: 0.22
Nodes (8): CGFloat, Content, AccountDevicesView, .body, .inventorySummary, String, URL, View

### Community 20 - "QuickControlView"
Cohesion: 0.29
Nodes (5): QuickControlView, .statusText, SettingsView, String, Void

## Knowledge Gaps
- **58 isolated node(s):** `PackageDescription`, `.inventorySummary`, `.refreshInterval`, `.deviceName`, `.temperatureControl` (+53 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppModel` connect `AppModel` to `ACProfile`, `.refresh`, `ACControlCore`, `AppDelegate`, `AccountDevice`, `FanSpeedOption`, `.loadDemo`, `AccountDevicesView`, `.applicationDidFinishLaunching`, `Bool`, `QuickControlView`?**
  _High betweenness centrality (0.351) - this node is a cross-community bridge._
- **Why does `ACProfile` connect `ACProfile` to `AppModel`, `.refresh`, `ACError`, `JSONValue`, `FixtureTransport`, `FanSpeedOption`, `fanProfile`, `.loadDemo`?**
  _High betweenness centrality (0.128) - this node is a cross-community bridge._
- **Why does `JSONValue` connect `JSONValue` to `ACProfile`, `.refresh`, `ACError`, `AccountDevice`, `FanSpeedOption`, `.loadDemo`?**
  _High betweenness centrality (0.125) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `AppModel` (e.g. with `AppDelegate` and `.applicationDidFinishLaunching()`) actually correct?**
  _`AppModel` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `ACProfile` (e.g. with `.testDoesNotGuessWriteCapabilitiesOrChangeMode()` and `.testPowerOnlyChangesOperationPreservingExistingTemperatureAndMode()`) actually correct?**
  _`ACProfile` has 5 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `.inventorySummary`, `.refreshInterval` to the rest of the system?**
  _58 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AppModel` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._