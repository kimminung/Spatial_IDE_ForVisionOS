import SwiftUI

/// 앱 실행 시 처음 보이는 최소 런처 윈도우.
///
/// visionOS는 앱을 처음 연결할 때 항상 `UIWindowSceneSessionRoleApplication` 역할의 씬을
/// 먼저 요청하므로, `ImmersiveSpace`만 선언된 앱은 씬을 찾지 못해 런치 즉시 크래시한다.
/// (Apple HIG도 "완전히 몰입형인 앱도 Shared Space에서 먼저 실행하는 것을 고려하라"고 안내한다.)
/// 이 뷰는 그 요구사항을 만족하는 최소한의 진입점 역할만 하며, CodeSpace로 진입하면
/// 곧바로 스스로를 닫아 이후에는 ImmersiveSpace만 보이게 한다.
struct LauncherView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isOpening = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("CodeSpace")
                .font(.largeTitle.bold())

            Text("코드 구조를 3D 공간에 펼쳐서 탐색하는 몰입형 개발 환경입니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await enterCodeSpace() }
            } label: {
                Text(isOpening ? "여는 중…" : "CodeSpace 진입")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isOpening)
        }
        .padding(40)
        .frame(width: 420)
    }

    private func enterCodeSpace() async {
        guard !isOpening, !appModel.isImmersiveSpaceOpened else { return }
        isOpening = true
        errorMessage = nil

        switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
        case .opened:
            appModel.isImmersiveSpaceOpened = true
            dismissWindow(id: AppModel.launcherWindowID)
        case .userCancelled:
            errorMessage = nil
        case .error:
            errorMessage = "CodeSpace를 여는 데 실패했습니다. 다시 시도해 주세요."
        @unknown default:
            errorMessage = "알 수 없는 상태입니다."
        }

        isOpening = false
    }
}
