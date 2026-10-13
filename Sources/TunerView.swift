import SwiftUI

private let mint = Color(red: 0.53, green: 0.94, blue: 0.74)
private let muted = Color(red: 0.49, green: 0.55, blue: 0.56)
private let amber = Color(red: 1, green: 0.73, blue: 0.40)

struct TunerView: View {
    @ObservedObject var model: TunerModel
    @State private var settings = false
    var accent: Color { model.frequency == nil ? muted : model.tuned ? mint : amber }
    var body: some View {
        Group {
            if model.compact { compactView } else { fullView }
        }
        .background(LinearGradient(colors: [Color(red: 0.085, green: 0.105, blue: 0.11), Color(red: 0.045, green: 0.058, blue: 0.064)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
    }
    var fullView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform").font(.system(size: 17, weight: .medium)).foregroundStyle(mint)
                Text("STILL").font(.system(size: 14, weight: .bold, design: .rounded)).tracking(4)
                Text("/  TUNER").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(muted)
                Spacer()
                Button { model.toggleCompact() } label: { Image(systemName: "chevron.up").foregroundStyle(muted) }
                    .buttonStyle(.plain).help("미니 모드로 접기").accessibilityLabel("미니 모드로 접기")
                Button { model.alwaysOnTop.toggle(); model.pinChanged() } label: {
                    Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin").foregroundStyle(model.alwaysOnTop ? mint : muted)
                }.buttonStyle(.plain).help("항상 위에 표시").accessibilityLabel("항상 위에 표시")
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(muted) }
                    .buttonStyle(.plain).padding(.leading, 13).help("튜너 설정").accessibilityLabel("튜너 설정")
                    .popover(isPresented: $settings) { settingsView }
            }.padding(.horizontal, 28).padding(.top, 27)

            HStack(spacing: 7) {
                Circle().fill(model.running ? mint : amber).frame(width: 5, height: 5)
                Text(model.demo ? "DEMO PREVIEW" : model.running ? "LISTENING" : "INPUT OFFLINE").tracking(2)
            }.font(.system(size: 9, weight: .semibold)).foregroundStyle(muted).padding(.top, 35)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.note).font(.system(size: 112, weight: .medium, design: .rounded)).tracking(-5)
                Text(model.octave).font(.system(size: 34, weight: .regular, design: .rounded)).foregroundStyle(muted).offset(x: 7, y: -5)
            }.foregroundStyle(model.frequency == nil ? Color.white.opacity(0.22) : .white).frame(height: 119)
            HStack(spacing: 8) {
                Text(model.frequency.map { String(format: "%.2f Hz", $0) } ?? "연주를 기다리고 있어요")
                if model.frequency != nil { Text("·"); Text(model.tuned ? "IN TUNE" : model.cents < 0 ? "FLAT" : "SHARP").foregroundStyle(accent) }
            }.font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(muted).frame(height: 20)

            NeedleMeter(cents: model.cents, active: model.frequency != nil, accent: accent)
                .frame(height: 117).padding(.horizontal, 35).padding(.top, 19)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(model.frequency == nil ? "—" : String(format: "%+.1f", model.cents)).font(.system(size: 35, weight: .medium, design: .monospaced)).contentTransition(.numericText())
                Text("cents").font(.system(size: 11)).foregroundStyle(muted)
            }.foregroundStyle(accent).frame(height: 42)
            Text(model.status).font(.system(size: 11, weight: .medium)).foregroundStyle(model.clipping ? amber : muted).lineLimit(2).multilineTextAlignment(.center).frame(height: 32).padding(.horizontal, 18)

            HStack(spacing: 9) {
                ForEach(Array([("E", 40), ("A", 45), ("D", 50), ("G", 55), ("B", 59), ("E", 64)].enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 6) {
                        Text("\(6 - index)").font(.system(size: 8, design: .monospaced)).foregroundStyle(muted)
                        Text(item.0).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(model.midi == item.1 ? mint : muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(model.midi == item.1 ? mint.opacity(0.09) : Color.white.opacity(0.025)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.midi == item.1 ? mint.opacity(0.3) : Color.white.opacity(0.035), lineWidth: 1))
                }
            }.padding(.horizontal, 30).padding(.top, 17)
            Spacer(minLength: 18)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            VStack(spacing: 13) {
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker").foregroundStyle(muted)
                    Menu {
                        if model.devices.isEmpty { Text("연결된 입력 장치 없음") }
                        ForEach(model.devices) { device in Button(device.name) { model.chooseDevice(device.uid) } }
                    } label: {
                        Text(model.selectedDevice?.name ?? "입력 장치 선택").lineLimit(1)
                    }.menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach(1...max(1, model.selectedDevice?.channels ?? 4), id: \.self) { ch in
                            Button("Input \(ch)\(ch == model.channel ? " ✓" : "")") { model.chooseChannel(ch) }
                        }
                    } label: { Text("IN \(model.channel)").font(.system(size: 10, weight: .semibold, design: .monospaced)) }
                    .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 8).padding(.vertical, 5).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                }.font(.system(size: 11))
                HStack(spacing: 8) {
                    Text("INPUT").tracking(1.2)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule().fill(model.clipping ? amber : mint.opacity(0.7)).frame(width: geo.size.width * max(0, min(1, (model.level + 65) / 65)))
                        }
                    }.frame(height: 3)
                    referenceMenu.padding(.leading, 9)
                    Text("·").foregroundStyle(muted)
                    Text("\(Int((model.selectedDevice?.rate ?? 48000) / 1000))k")
                }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(muted)
            }.padding(.horizontal, 28).padding(.vertical, 18)
        }
        .background(LinearGradient(colors: [Color(red: 0.085, green: 0.105, blue: 0.11), Color(red: 0.045, green: 0.058, blue: 0.064)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark).frame(minWidth: 400, idealWidth: 440, maxWidth: .infinity, minHeight: 640, idealHeight: 650, maxHeight: .infinity)
    }
    var referenceMenu: some View {
        Menu {
            Text("A4 기준음 · 비교하는 튜너와 동일하게 설정")
            ForEach(430...450, id: \.self) { hz in
                Button("\(hz) Hz\(Int(model.reference) == hz ? " ✓" : "")") { model.setReference(Double(hz)) }
            }
        } label: { Text("A4 \(Int(model.reference)) Hz").font(.system(size: 10, weight: .medium, design: .monospaced)) }
        .menuStyle(.borderlessButton).fixedSize().help("기준음 변경 · Helix와 같은 값으로 맞추세요")
    }
    var compactView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Circle().fill(model.running ? mint : amber).frame(width: 5, height: 5)
                Text(model.demo ? "STILL / DEMO" : "STILL").font(.system(size: 10, weight: .bold)).tracking(2)
                Spacer()
                Button { model.alwaysOnTop.toggle(); model.pinChanged() } label: { Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin").foregroundStyle(model.alwaysOnTop ? mint : muted) }
                    .buttonStyle(.plain).help("항상 위에 표시").accessibilityLabel("항상 위에 표시")
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(muted) }
                    .buttonStyle(.plain).help("튜너 설정").accessibilityLabel("튜너 설정")
                    .popover(isPresented: $settings) { settingsView }
                Button { model.toggleCompact() } label: { Image(systemName: "chevron.down").foregroundStyle(muted) }
                    .buttonStyle(.plain).help("전체 화면 펼치기").accessibilityLabel("전체 화면 펼치기")
            }.padding(.top, 10)
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(model.note).font(.system(size: 70, weight: .medium, design: .rounded)).tracking(-3)
                    Text(model.octave).font(.system(size: 23, design: .rounded)).foregroundStyle(muted)
                }.foregroundStyle(model.frequency == nil ? .white.opacity(0.25) : .white)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(model.frequency == nil ? "—" : String(format: "%+.1f", model.cents)).font(.system(size: 30, weight: .medium, design: .monospaced))
                        Text("cents").font(.system(size: 9)).foregroundStyle(muted)
                    }.foregroundStyle(accent)
                    Text(model.frequency.map { String(format: "%.2f Hz", $0) } ?? "한 줄씩 연주해 주세요")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }
            }.frame(height: 91).padding(.top, 5)
            NeedleMeter(cents: model.cents, active: model.frequency != nil, accent: accent).frame(height: 91)
            Spacer(minLength: 2)
            HStack {
                Text(model.status).lineLimit(1).font(.system(size: 10)).foregroundStyle(model.clipping ? amber : muted)
                Spacer(minLength: 0)
            }.padding(.bottom, 10)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            HStack {
                Text("IN \(model.channel)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(muted)
                Spacer()
                referenceMenu.foregroundStyle(muted)
            }.padding(.vertical, 10)
        }.padding(.horizontal, 22)
        .frame(minWidth: 340, idealWidth: 380, maxWidth: .infinity, minHeight: 290, idealHeight: 290, maxHeight: .infinity)
    }
    var settingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("튜너 설정").font(.headline)
            Toggle("항상 위에 표시", isOn: Binding(get: { model.alwaysOnTop }, set: { model.alwaysOnTop = $0; model.pinChanged() }))
            HStack { Text("기준 음 A4"); Spacer(); Stepper("\(Int(model.reference)) Hz", value: Binding(get: { model.reference }, set: { model.setReference($0) }), in: 430...450, step: 1) }
            Text("다른 튜너와 비교할 때 A4 기준음을 같게 맞추세요. 440 ↔ 441 Hz는 약 3.93 cents 차이입니다.").font(.caption).foregroundStyle(.secondary)
            Text("±2 cents 이내이면 녹색으로 표시합니다.\n아래 E A D G B E는 표준 튜닝 가이드입니다.\n다른 튜닝도 모든 반음을 자동으로 감지합니다.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("입력 신호만 분석합니다. 소리를 출력하거나 기기의 샘플레이트·버퍼·TotalMix 설정을 변경하지 않습니다. 원음은 기존 TotalMix/Cubase 모니터링으로 들으세요.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.permissionDenied {
                Button("마이크 권한 설정 열기") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
            }
            Button("입력 다시 연결") { model.requestPermission() }
        }.padding(22).frame(width: 320)
    }
}

struct NeedleMeter: View {
    let cents: Double
    let active: Bool
    let accent: Color
    var body: some View {
        Canvas { context, size in
            let inset = 14.0
            let width = size.width - inset * 2, center = size.width / 2
            let y = 62.0
            var baseline = Path(); baseline.move(to: CGPoint(x: inset, y: y)); baseline.addLine(to: CGPoint(x: size.width - inset, y: y))
            context.stroke(baseline, with: .color(.white.opacity(0.12)), lineWidth: 1)
            let zone = CGRect(x: center - width * 0.025, y: 17, width: width * 0.05, height: 48)
            context.fill(Path(roundedRect: zone, cornerRadius: 4), with: .color(mint.opacity(0.09)))
            for tick in -10...10 {
                let x = center + Double(tick) * width / 20
                let major = tick % 5 == 0
                var p = Path(); p.move(to: CGPoint(x: x, y: y - (major ? 24 : 11))); p.addLine(to: CGPoint(x: x, y: y))
                context.stroke(p, with: .color(tick == 0 ? mint : .white.opacity(major ? 0.35 : 0.15)), lineWidth: tick == 0 ? 2 : 1)
                if major { context.draw(Text(tick == 0 ? "0" : String(format: "%+d", tick * 5)).font(.system(size: 9, design: .monospaced)).foregroundColor(muted), at: CGPoint(x: x, y: y + 21)) }
            }
            if active {
                let x = center + max(-50, min(50, cents)) / 100 * width
                var needle = Path(); needle.move(to: CGPoint(x: x, y: 9)); needle.addLine(to: CGPoint(x: x, y: 65))
                context.stroke(needle, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                var triangle = Path(); triangle.move(to: CGPoint(x: x - 5, y: 4)); triangle.addLine(to: CGPoint(x: x + 5, y: 4)); triangle.addLine(to: CGPoint(x: x, y: 11)); triangle.closeSubpath()
                context.fill(triangle, with: .color(accent))
            }
            context.draw(Text("♭").font(.system(size: 15)).foregroundColor(muted), at: CGPoint(x: inset, y: 9))
            context.draw(Text("♯").font(.system(size: 15)).foregroundColor(muted), at: CGPoint(x: size.width - inset, y: 9))
        }.accessibilityLabel("음정 편차 \(String(format: "%.1f", cents)) 센트")
    }
}
