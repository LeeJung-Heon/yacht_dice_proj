import SwiftUI
import PhotosUI
import GameCore

struct CupPongCustomizationView: View {
    let service: SupabaseService
    var store: CupPongCustomizationStore = .shared
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCup = 9
    @State private var selection: PhotosPickerItem?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var syncMessage: String?
    @State private var needsSync = false
    private var green: Color { theme.cupPongBackdrop }
    private var cream: Color { theme.cupPongPaper }
    private let rows = [[0, 1, 2, 3], [4, 5, 6], [7, 8], [9]]

    var body: some View {
        let pickerForeground = green
        let pickerBackground = cream
        let photoButtonTitle = store.image(for: selectedCup) == nil ? "사진 넣기" : "사진 바꾸기"
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 5) {
                        Text("나만의 컵").font(.system(.largeTitle, design: .serif, weight: .bold))
                        Text("사진 한 장으로, 우리만의 게임").font(.subheadline).foregroundStyle(cream.opacity(0.75))
                    }.padding(.top, 10)
                    CupPongTableView(cups: (0..<10).map { $0 == selectedCup }, owner: "컵 \(selectedCup + 1)",
                                     ball: nil, vanishing: nil, customization: store, focusedCup: selectedCup)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(alignment: .bottomLeading) {
                            Text("CUP \(String(format: "%02d", selectedCup + 1))").font(.caption.monospaced().weight(.bold))
                                .padding(12).background(green.opacity(0.8), in: Capsule()).padding(12)
                        }
                    VStack(spacing: 8) {
                        ForEach(rows.indices, id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(rows[row], id: \.self) { cup in cupButton(cup) }
                            }
                        }
                    }
                    .disabled(isBusy)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                            Label(photoButtonTitle, systemImage: "photo")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                                .foregroundStyle(pickerForeground).background(pickerBackground, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .accessibilityIdentifier("cuppong.customize.photo")
                        .disabled(isBusy)
                        Button {
                            isBusy = true
                            Task {
                                defer { isBusy = false }
                                do {
                                    try store.removeImage(for: selectedCup)
                                    needsSync = true
                                    await sync()
                                } catch { errorMessage = error.localizedDescription }
                            }
                        } label: {
                            Image(systemName: "trash").frame(width: 48, height: 48)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .accessibilityLabel("선택한 컵 사진 삭제")
                        .accessibilityIdentifier("cuppong.customize.remove")
                        .disabled(isBusy || store.image(for: selectedCup) == nil)
                    }
                    VStack(spacing: 6) {
                        if isBusy { ProgressView("사진을 적용하는 중…").tint(cream) }
                        Text("온라인 대전에서는 상대에게도 보입니다.").font(.caption)
                        Text("사진은 가운데를 정사각형으로 잘라 컵에 붙입니다.")
                            .font(.caption2).foregroundStyle(cream.opacity(0.65))
                        if let syncMessage {
                            Text(syncMessage).font(.caption).multilineTextAlignment(.center)
                        }
                        if needsSync, !isBusy {
                            Button("온라인 공유 다시 시도") {
                                isBusy = true
                                Task { await sync(); isBusy = false }
                            }.font(.caption.weight(.semibold))
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 24)
            }
            .background(green).foregroundStyle(cream)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }.foregroundStyle(cream).disabled(isBusy)
                        .accessibilityIdentifier("cuppong.customize.done")
                }
            }
            .toolbarBackground(green, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .interactiveDismissDisabled(isBusy)
            .task(id: selection) {
                guard let selection else { return }
                let cup = selectedCup
                isBusy = true
                defer { isBusy = false; self.selection = nil }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw CupPongCustomizationStore.PhotoError.invalidImage
                    }
                    try Task.checkCancellation()
                    try store.setImage(data: data, for: cup)
                    needsSync = true
                    await sync()
                } catch is CancellationError { }
                catch { errorMessage = error.localizedDescription }
            }
            .alert("사진을 적용하지 못했습니다", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("확인", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func cupButton(_ cup: Int) -> some View {
        Button { selectedCup = cup } label: {
            ZStack {
                Circle().fill(selectedCup == cup ? cream : .white.opacity(0.08))
                if let image = store.image(for: cup) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                } else {
                    Text("\(cup + 1)").font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(selectedCup == cup ? green : cream)
                }
            }
            .frame(width: 48, height: 48)
            .overlay(Circle().strokeBorder(selectedCup == cup ? cream : .clear, lineWidth: 3).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("컵 \(cup + 1)\(store.image(for: cup) != nil ? ", 사진 있음" : "")")
        .accessibilityAddTraits(selectedCup == cup ? .isSelected : [])
        .accessibilityIdentifier("cuppong.customize.cup.\(cup)")
    }

    private func sync() async {
        do {
            try await CupPongPhotoService(service: service).publish(store)
            needsSync = false
            syncMessage = "온라인 공유 완료"
        } catch {
            syncMessage = "기기에 저장했습니다. 온라인 공유는 다시 시도해 주세요."
        }
    }
}
