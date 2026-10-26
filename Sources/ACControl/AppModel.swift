import AppKit
import Combine
import ServiceManagement
import ACControlCore

@MainActor
final class AppModel: ObservableObject {
    @Published var draft: Double = 22
    @Published var isDragging = false
    @Published private(set) var snapshot: ACSnapshot?
    @Published private(set) var profile: ACProfile?
    @Published private(set) var devices: [AccountDevice] = []
    @Published private(set) var discoveryError: String?
    @Published private(set) var hasLoadedDevices = false
    @Published private(set) var selectedID = ""
    @Published private(set) var fault: String? = "Preparando conexão…"
    @Published private(set) var isWorking = false
    @Published private(set) var phase = ""
    @Published private(set) var tokenConfigured = false
    @Published private(set) var loginStatus = ""
    @Published private(set) var launchAtLogin = false
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval") }
    }
    let demo: Bool
    let envURL: URL
    private let defaults: UserDefaults
    private var client: ThinQClient?
    private var pollingTask: Task<Void, Never>?
    private var failureCount = 0
    private var isSuspended = false
    private var demoSnapshots: [String: ACSnapshot] = [:]

    init(demo: Bool) {
        self.demo = demo
        defaults = demo ? UserDefaults(suiteName: "com.fesaab.ac-control.demo")! : .standard
        let stored = defaults.double(forKey: "refreshInterval")
        refreshInterval = [30, 60, 120, 300].contains(stored) ? stored : 60
        let path = ProcessInfo.processInfo.environment["AC_CONTROL_ENV_FILE"]
            ?? Bundle.main.object(forInfoDictionaryKey: "ACControlEnvPath") as? String
            ?? FileManager.default.currentDirectoryPath + "/.env"
        envURL = URL(fileURLWithPath: path)
        if demo { loadDemo(isOn: true) }
    }

    var selectedDevice: AccountDevice? { devices.first { $0.id == selectedID } }
    var deviceName: String { selectedDevice?.name ?? "AC Control" }
    var temperatureControl: TemperatureControl? { profile?.temperatureControl(jobMode: snapshot?.jobMode) }
    var canControl: Bool { fault == nil && snapshot != nil && !isWorking && !isSuspended && !isStale }
    var fanSpeedControl: FanSpeedControl? { profile?.fanSpeedControl }
    var currentFanOptionID: String {
        guard let snapshot else { return "" }
        return fanSpeedControl?.currentOption(in: snapshot)?.id ?? ""
    }
    var canSetFanSpeed: Bool { canControl && !isDragging && snapshot?.isOn == true && fanSpeedControl != nil }
    var canSetTemperature: Bool { canControl && snapshot?.isOn == true && temperatureControl != nil }
    var isStale: Bool { snapshot?.isStale(interval: refreshInterval) ?? false }
    var warning: String? {
        if let fault { return fault }
        if isStale { return "Estado desatualizado. Consulte novamente antes de controlar o aparelho." }
        guard let snapshot else { return "Estado ainda não disponível." }
        if snapshot.room == nil { return "A LG não informou a temperatura ambiente do aparelho." }
        if snapshot.isOn && snapshot.target == nil { return "A LG não informou a temperatura configurada." }
        return nil
    }
    var barTitle: String { warning == nil ? snapshot?.barTitle() ?? "" : "" }
    var barSymbol: String { warning != nil ? "exclamationmark.triangle" : snapshot?.isOn == true ? "snowflake" : "thermometer.medium" }
    var barHelp: String {
        if let warning { return "AC Control — \(warning)" }
        guard let snapshot else { return "AC Control" }
        let room = snapshot.room.map(temperatureLabel) ?? "—"
        let target = snapshot.target.map(temperatureLabel) ?? "—"
        return "\(deviceName) · \(snapshot.isOn ? "Ligado" : "Desligado") · Configurada: \(target)C · Ambiente: \(room)C"
    }

    func start() {
        guard !demo else { return }
        syncLoginItem()
        Task { await reconnect() }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = self.failureCount == 0 ? self.refreshInterval : min(900, max(self.refreshInterval, 60) * pow(2, Double(min(self.failureCount, 4))))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }
    func stop() { pollingTask?.cancel() }

    private func configuration() throws -> LGConfiguration {
        let text = (try? String(contentsOf: envURL, encoding: .utf8)) ?? ""
        var values = DotEnv.parse(text)
        for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("LG_THINQ_") { values[key] = value }
        tokenConfigured = !(values["LG_THINQ_PAT"] ?? "").isEmpty
        let clientID = defaults.string(forKey: "clientID") ?? UUID().uuidString
        defaults.set(clientID, forKey: "clientID")
        return try LGConfiguration(values: values, fallbackClientID: clientID)
    }
    func reconnect() async {
        guard !isWorking, !demo else { return }
        client = nil; profile = nil; snapshot = nil; devices = []; selectedID = ""
        hasLoadedDevices = false; discoveryError = nil
        await refresh()
    }
    func selectDevice(_ id: String) async {
        guard !isWorking, !isDragging, id != selectedID,
              let device = devices.first(where: { $0.id == id }), device.isControllable else { return }
        defaults.set(id, forKey: "deviceID")
        selectedID = id; profile = nil; snapshot = nil
        fault = "Carregando \(device.name)…"
        if demo {
            let stored = demoSnapshots[id]
            loadDemo(isOn: stored?.isOn ?? false, target: stored?.target ?? 23, missingRoom: stored?.room == nil && stored != nil)
            return
        }
        await refresh()
    }
    func reloadDevices() async {
        if demo { discoveryError = nil; return }
        await refresh(includingDevices: true)
    }

    func refresh(includingDevices: Bool = false) async {
        guard !demo, !isWorking, !isSuspended, !isDragging else { return }
        isWorking = true; phase = "Consultando LG…"
        defer { isWorking = false; phase = "" }
        do {
            if client == nil { client = ThinQClient(configuration: try configuration()) }
            guard let client else { throw ACError.invalidResponse }
            if !hasLoadedDevices || includingDevices {
                do {
                    let inventory = try await client.devices()
                    devices = inventory
                    hasLoadedDevices = true
                    discoveryError = nil
                } catch {
                    discoveryError = userMessage(error)
                    throw error
                }
                if !devices.contains(where: { $0.id == selectedID && $0.isControllable }) {
                    selectedID = ""; profile = nil; snapshot = nil
                }
            }
            if selectedID.isEmpty {
                let choice = DeviceSelection.resolve(devices: devices, savedID: defaults.string(forKey: "deviceID"))
                switch choice {
                case .selected(let id): selectedID = id
                case .needsSelection: throw ACError.selectionRequired
                case .noSupportedDevices: throw ACError.noDevices
                case .unavailable: throw ACError.configuration("Aparelho escolhido não está disponível nesta conta. Selecione outro nas configurações.")
                }
            }
            guard selectedDevice?.isControllable == true else { throw ACError.selectionRequired }
            if profile == nil { profile = try await client.profile(id: selectedID) }
            snapshot = try await client.state(id: selectedID)
            fault = nil; failureCount = 0
        } catch {
            fault = userMessage(error)
            failureCount += 1
        }
    }

    func setPower(_ on: Bool) async {
        guard canControl, let profile else { return }
        if demo { loadDemo(isOn: on, target: snapshot?.target ?? 22); return }
        do {
            let payload = try profile.powerPayload(on: on)
            await command(payload: payload) { $0.isOn == on }
        } catch { fault = userMessage(error) }
    }
    func setTemperature(_ value: Double) async {
        guard canSetTemperature, let control = temperatureControl else { return }
        let snapped = control.range.snapped(value)
        if demo { loadDemo(isOn: true, target: snapped); return }
        do {
            let payload = try control.payload(value: snapped)
            await command(payload: payload) { $0.target.map { abs($0 - snapped) < 0.01 } ?? false }
        } catch { fault = userMessage(error) }
    }
    func setFanSpeed(_ optionID: String) async {
        guard canSetFanSpeed, let control = fanSpeedControl, optionID != currentFanOptionID else { return }
        do {
            let payload = try control.payload(optionID: optionID)
            if demo {
                let value = payload["airFlow"][control.property]
                loadDemo(isOn: true, target: snapshot?.target ?? 22, fanValue: value)
                return
            }
            await command(payload: payload) { control.isConfirmed(optionID: optionID, snapshot: $0) }
        } catch { fault = userMessage(error) }
    }

    private func command(payload: JSONValue, confirmed: (ACSnapshot) -> Bool) async {
        guard let client else { return }
        isWorking = true; phase = "Aplicando ajuste…"
        defer { isWorking = false; phase = "" }
        do {
            // A control is sent exactly once. A timeout must never duplicate a write.
            try await client.control(id: selectedID, payload: payload)
            phase = "Confirmando no aparelho…"
            for attempt in 0..<3 {
                if attempt > 0 { try await Task.sleep(for: .seconds(2)) }
                let current = try await client.state(id: selectedID)
                snapshot = current
                if confirmed(current) { fault = nil; failureCount = 0; return }
            }
            fault = "A LG recebeu o comando; o estado ainda não confirmou a alteração. Atualize em alguns instantes."
        } catch { fault = userMessage(error) }
    }
    private func userMessage(_ error: Error) -> String {
        if let error = error as? ACError { return error.localizedDescription }
        if let error = error as? URLError, error.code == .timedOut {
            return "A LG demorou a responder. O comando não será reenviado automaticamente. Atualize o estado."
        }
        return "Não foi possível consultar a LG. Confira sua conexão e tente atualizar."
    }

    func suspend() { isSuspended = true; fault = "Mac em repouso. Estado será atualizado ao despertar." }
    func wake() { isSuspended = false; snapshot = nil; fault = "Atualizando após repouso…"; Task { await refresh() } }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !demo else { return }
        defaults.set(enabled, forKey: "launchAtLogin")
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            syncLoginItem(registerIfNeeded: false)
        } catch { loginStatus = "macOS não aplicou a alteração. Confira Itens de Início nos Ajustes do Sistema." }
    }
    func syncLoginItem(registerIfNeeded: Bool = true) {
        guard !demo else { loginStatus = "Desativado na demonstração."; return }
        let wanted = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        if registerIfNeeded && wanted && SMAppService.mainApp.status == .notRegistered {
            setLaunchAtLogin(true)
            return
        }
        launchAtLogin = wanted
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "Ativado no macOS."
        case .requiresApproval: loginStatus = "Autorize AC Control em Ajustes do Sistema → Geral → Itens de Início."
        case .notRegistered: loginStatus = wanted ? "Será ativado ao abrir o app empacotado." : "Desativado."
        case .notFound: loginStatus = "Abra o app empacotado para ativar."
        @unknown default: loginStatus = "Confira Itens de Início no macOS."
        }
    }
    func openEnvFile() {
        NSWorkspace.shared.open([envURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration())
    }
    func demoState(_ state: String) {
        guard demo else { return }
        switch state {
        case "off": loadDemo(isOn: false)
        case "offline": fault = "Sem conexão com a LG. Confira sua internet e tente novamente."
        case "missing": loadDemo(isOn: false, missingRoom: true)
        default: loadDemo(isOn: true)
        }
    }
    private func loadDemo(isOn: Bool, target: Double = 22, missingRoom: Bool = false, fanValue: JSONValue? = nil) {
        if devices.isEmpty {
            devices = (try! JSONValue.decode(#"[{"deviceId":"demo-ac","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Quarto","modelName":"S3NQ09AA31A"}},{"deviceId":"demo-office","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","alias":"Escritório","modelName":"S3NQ12JA31A"}},{"deviceId":"demo-washer","deviceInfo":{"deviceType":"DEVICE_WASHER","alias":"Lavanderia","modelName":"LG WashTower"}}]"#)).array!.compactMap(AccountDevice.init)
            hasLoadedDevices = true
        }
        if selectedID.isEmpty { selectedID = "demo-ac" }
        profile = try! ACProfile(json: .decode(#"{"property":{"airFlow":{"windStrengthDetail":{"mode":["r","w"],"type":"enum","value":{"w":["AUTO","LOW","MID","HIGH","POWER"]}}},"operation":{"airConOperationMode":{"mode":["r","w"],"type":"enum","value":{"w":["POWER_ON","POWER_OFF"]}}},"temperatureInUnits":[{"unit":"C","targetTemperature":{"mode":["r","w"],"type":"range","value":{"w":{"min":18,"max":30,"step":1}}}}]}}"#))
        let room = missingRoom ? "null" : selectedID == "demo-office" ? "24" : "26"
        let fan = fanValue ?? demoSnapshots[selectedID]?.fanValues["windStrengthDetail"] ?? .string("AUTO")
        let fanJSON = String(data: try! JSONEncoder().encode(fan), encoding: .utf8)!
        snapshot = try! ACSnapshot(json: .decode("{\"airFlow\":{\"windStrengthDetail\":\(fanJSON)},\"operation\":{\"airConOperationMode\":\"\(isOn ? "POWER_ON" : "POWER_OFF")\"},\"airConJobMode\":{\"currentJobMode\":\"COOL\"},\"temperatureInUnits\":[{\"unit\":\"C\",\"targetTemperature\":\(target),\"currentTemperature\":\(room)}]}"))
        demoSnapshots[selectedID] = snapshot
        fault = nil
    }
}
