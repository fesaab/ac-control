import SwiftUI
import ACControlCore

struct AccountDevicesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(inventorySummary)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.reloadDevices() } } label: {
                    Label("Atualizar lista", systemImage: "arrow.clockwise")
                }.disabled(model.isWorking || model.isDragging)
            }
            if model.devices.isEmpty {
                Text(model.hasLoadedDevices ? "A LG não retornou dispositivos para esta conta." : "Carregue a conta LG para ver seus dispositivos.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.devices) { device in
                            deviceRow(device)
                        }
                    }
                }.frame(height: min(240, CGFloat(model.devices.count) * 66))
            }
            if let error = model.discoveryError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if let selected = model.selectedDevice {
                HStack(alignment: .firstTextBaseline) {
                    Text("Controlando").foregroundStyle(.secondary)
                    Spacer()
                    Text(selected.name).fontWeight(.medium)
                }
                Text("ID: " + selected.id).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Text("Selecione um ar-condicionado para ativar os controles.").font(.caption).foregroundStyle(.secondary)
            }
            Text("A escolha fica salva neste Mac. Outros tipos de dispositivo aparecem para identificação; o controle deste app atende ares-condicionados.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inventorySummary: String {
        let count = model.devices.count
        let airCount = model.devices.filter(\.isControllable).count
        let all = count == 1 ? "1 dispositivo" : "\(count) dispositivos"
        let airs = airCount == 1 ? "1 ar-condicionado" : "\(airCount) ares-condicionados"
        return all + " · " + airs
    }

    private func deviceRow(_ device: AccountDevice) -> some View {
        let selected = device.id == model.selectedID
        return Button {
            Task { await model.selectDevice(device.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: device.symbol).font(.system(size: 19))
                    .foregroundStyle(device.isControllable ? Color.blue : Color.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(device.kindDescription + (device.model.map { " · " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if model.devices.filter({ $0.name == device.name }).count > 1 {
                        Text("ID: " + device.id).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                if device.isControllable {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.blue : Color.secondary)
                        .font(.system(size: 18))
                } else {
                    Text("Não suportado").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.blue.opacity(0.10) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!device.isControllable || model.isWorking || model.isDragging)
        .accessibilityLabel(device.name + ", " + device.kindDescription + (selected ? ", selecionado" : device.isControllable ? ", selecionar para controlar" : ", controle não suportado"))
    }
}
