import SwiftUI
import UIKit

/// 머리글의 😊 단추. 누르면 시스템 이모지 키보드가 열리고, 이모지 하나를 고르면 보내고 닫힌다.
/// 다시 누르거나 키보드 밖을 누르면 보내지 않고 닫힌다. 간격 안에는 흐리게 잠긴다.
struct ReactionButton: View {
    let canSend: Bool
    let send: (String) -> Void
    @Environment(\.theme) private var theme
    @State private var isTyping = false

    var body: some View {
        Button { isTyping.toggle() } label: {
            Text("😊").font(.system(size: 17))
                .frame(width: 32, height: 32)
                .background(Circle().fill(isTyping ? theme.brass : theme.ivory.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .opacity(canSend ? 1 : 0.4)
        .disabled(!canSend)
        .accessibilityLabel("이모지 보내기")
        .accessibilityIdentifier("reaction.button")
        .background {
            EmojiInput(isActive: $isTyping) { emoji in
                send(emoji)
                isTyping = false
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        // 키보드를 연 채 화면을 떠나면 키보드가 남지 않게 닫는다.
        .onDisappear { isTyping = false }
    }
}

/// 보이지 않는 입력 칸. 첫 응답자가 되면 이모지 키보드를 띄우고, 들어온 글자는 칸에 남기지 않고 넘긴다.
private struct EmojiInput: UIViewRepresentable {
    @Binding var isActive: Bool
    let onInput: (String) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.tintColor = .clear
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        // 뷰를 고치는 도중에 응답자를 바꾸면 SwiftUI 상태를 그 안에서 고치게 되므로 다음 차례로 미룬다.
        if isActive, !field.isFirstResponder {
            DispatchQueue.main.async { _ = field.becomeFirstResponder() }
        } else if !isActive, field.isFirstResponder {
            DispatchQueue.main.async { _ = field.resignFirstResponder() }
        }
    }

    static func dismantleUIView(_ field: EmojiTextField, coordinator: Coordinator) {
        _ = field.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiInput
        init(parent: EmojiInput) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if !string.isEmpty { parent.onInput(string) }
            return false
        }

        /// 키보드 밖을 눌러 내려갔을 때 단추의 상태를 맞춘다.
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isActive { parent.isActive = false }
        }
    }
}

/// 이모지 키보드로 열리는 입력 칸. 이모지 키보드를 지운 사용자에게는 기본 키보드가 열리고, 그때 친 글자는 판정에서 버려진다.
final class EmojiTextField: UITextField {
    private var outsideTap: UITapGestureRecognizer?

    /// 비워 두어야 시스템이 마지막에 쓴 키보드를 기억해 되돌리지 않는다.
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        // 키보드 밖을 누르면 닫는다. 그 탭이 판에 수로 들어가지 않도록 삼킨다.
        if became, outsideTap == nil, let window {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOutside))
            tap.cancelsTouchesInView = true
            window.addGestureRecognizer(tap)
            outsideTap = tap
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        if let outsideTap {
            outsideTap.view?.removeGestureRecognizer(outsideTap)
            self.outsideTap = nil
        }
        return super.resignFirstResponder()
    }

    @objc private func tappedOutside() { _ = resignFirstResponder() }
}
