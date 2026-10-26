import SwiftUI
import ServiceManagement
import ACControlCore

struct QuickControlView: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "snowflake")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(.blue)
                    .frame(width: 38, height: 38).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.deviceName).font(.headline)
                        if model.demo { Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange) }
                    }
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.setPower(!(model.snapshot?.isOn ?? false)) }
                } label: {
                    Image(systemName: "power").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(model.snapshot?.isOn == true ? Color.white : Color.secondary)
                        .frame(width: 36, height: 36)
                        .background(model.snapshot?.isOn == true ? Color.blue : Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canControl || model.profile?.canSwitchPower != true)
                .accessibilityLabel(model.snapshot?.isOn == true ? "Desligar ar-condicionado" : "Ligar ar-condicionado")
                .help(model.snapshot?.isOn == true ? "Desligar" : "Ligar")
            }

            if let warning = model.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Temperatura desejada").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(temperatureLabel(model.draft) + "C").font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(model.canSetTemperature || model.isDragging ? Color.primary : Color.secondary)
                }
                let range = model.temperatureControl?.range
                Slider(value: $model.draft, in: (range?.min ?? 18)...(range?.max ?? 30), step: range?.step ?? 1,
                       onEditingChanged: { editing in
                    model.isDragging = editing
                    if !editing { Task { await model.setTemperature(model.draft) } }
                })
                .tint(.blue)
                .disabled(!model.canSetTemperature)
                .accessibilityLabel("Temperatura desejada")
                .accessibilityValue(temperatureLabel(model.draft) + " Celsius")
                HStack {
                    Text(temperatureLabel(range?.min ?? 18) + "C")
                    Spacer()
                    Text(temperatureLabel(range?.max ?? 30) + "C")
                }.font(.caption2).foregroundStyle(.tertiary)
                if !model.canSetTemperature && model.warning == nil && !model.isWorking {
                    Text(model.snapshot?.isOn == false ? "Ligue o ar para ajustar a temperatura." : "Ajuste indisponível no modo atual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let control = model.fanSpeedControl {
                HStack {
                    Label("Ventilador", systemImage: "fan").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Velocidade do ventilador", selection: Binding(get: { model.currentFanOptionID }, set: { id in
                        Task { await model.setFanSpeed(id) }
                    })) {
                        if model.currentFanOptionID.isEmpty { Text("Não informado").tag("") }
                        ForEach(control.options) { option in Text(option.title).tag(option.id) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 165)
                    .disabled(!model.canSetFanSpeed)
                    .accessibilityLabel("Velocidade do ventilador")
                }.font(.subheadline)
            } else if model.profile != nil {
                HStack {
                    Label("Ventilador", systemImage: "fan").foregroundStyle(.secondary)
                    Spacer()
                    Text("Indisponível").font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline)
            }

            HStack {
                Label("Temperatura ambiente", systemImage: "thermometer.medium").foregroundStyle(.secondary)
                Spacer()
                Text(model.warning == nil ? model.snapshot?.room.map { temperatureLabel($0) + "C" } ?? "—" : "—")
                    .fontWeight(.medium).monospacedDigit()
            }.font(.subheadline)

            HStack {
                if model.isWorking {
                    ProgressView().controlSize(.mini)
                    Text(model.phase)
                } else if let snapshot = model.snapshot, model.warning == nil {
                    Text("Consulta LG às " + snapshot.queriedAt.formatted(date: .omitted, time: .standard))
                } else { Text("Estado indisponível") }
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(model.isWorking || model.demo)
                    .accessibilityLabel("Atualizar estado").help("Consultar LG agora")
            }.font(.caption2).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(action: openSettings) {
                    Label("Configurações…", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command)
                Button("Sair") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.subheadline)
        }
        .padding(16).frame(width: 336)
        .onAppear { syncDraft() }
        .onChange(of: model.snapshot) { _, _ in if !model.isDragging { syncDraft() } }
    }
    private var statusText: String {
        if model.warning != nil { return "Requer atenção" }
        return model.snapshot?.isOn == true ? "Ligado · LG ThinQ" : "Desligado · LG ThinQ"
    }
    private func syncDraft() {
        let value = model.snapshot?.target ?? 22
        model.draft = model.temperatureControl?.range.snapped(value) ?? min(30, max(18, value))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Abrir ao iniciar sessão no macOS", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                    .disabled(model.demo)
                if !model.loginStatus.isEmpty {
                    Text(model.loginStatus).font(.caption).foregroundStyle(.secondary)
                }
                if SMAppService.mainApp.status == .requiresApproval && !model.demo {
                    Button("Abrir Itens de Início") { SMAppService.openSystemSettingsLoginItems() }
                }
                Picker("Consultar estado a cada", selection: $model.refreshInterval) {
                    Text("30 segundos").tag(30.0)
                    Text("1 minuto").tag(60.0)
                    Text("2 minutos").tag(120.0)
                    Text("5 minutos").tag(300.0)
                }.disabled(model.demo)
            }
            Section("Dispositivos da conta") {
                AccountDevicesView(model: model)
            }
            Section("Conta LG ThinQ") {
                LabeledContent("Token PAT", value: model.demo ? "Demonstração sem conexão" : model.tokenConfigured ? "Configurado no .env" : "Não configurado")
                Text(model.envURL.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Editar .env") { model.openEnvFile() }
                    Button("Recarregar configuração") { Task { await model.reconnect() } }
                        .disabled(model.isWorking || model.demo)
                    Link("Gerar token ↗", destination: URL(string: "https://connect-pat.lgthinq.com/tokens")!)
                }
                Text("Token lido de LG_THINQ_PAT. Sem Keychain. País/região definidos no .env; use a mesma conta cadastrada no aplicativo ThinQ.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Leituras") {
                Text("A temperatura ambiente é a leitura do sensor do ar. A LG pode entregar valores com atraso, inclusive com o aparelho desligado. O horário mostrado indica a consulta à nuvem, não a coleta do sensor.")
                    .font(.caption).foregroundStyle(.secondary)
                if let warning = model.warning { Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }
            if model.demo {
                Section("Demonstração local") {
                    HStack {
                        Button("Ligado") { model.demoState("on") }
                        Button("Desligado") { model.demoState("off") }
                        Button("Offline") { model.demoState("offline") }
                        Button("Sem sensor") { model.demoState("missing") }
                    }
                    Text("Dados fictícios. Nenhuma chamada à LG; início automático desativado.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped).frame(width: 560, height: model.demo ? 780 : 640)
        .onAppear { model.syncLoginItem(registerIfNeeded: false) }
    }
}
