import SwiftUI

/// CodeSpace 앱 엔트리 포인트.
///
/// PRD 요구사항대로 실제 작업 공간은 `ImmersiveSpace` 하나로 구성하지만,
/// visionOS는 앱을 처음 연결할 때 항상 `UIWindowSceneSessionRoleApplication`(윈도우) 역할의
/// 씬을 요청하기 때문에 `WindowGroup`을 최소 1개 선언해야 한다.
/// (선언하지 않으면 "no scenes declared in your app body match this role" 크래시가 발생한다.)
/// `LauncherView`는 진입 버튼만 제공하는 최소 윈도우이며, ImmersiveSpace가 열리면 스스로 닫혀
/// 이후에는 몰입 공간만 남는다.
@main
struct CodeSpaceApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: AppModel.launcherWindowID) {
            LauncherView()
                .environment(appModel)
        }

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            CodeSpaceImmersiveView()
                .environment(appModel)
        }
        // 기본은 .progressive: 디지털 크라운으로 패스스루가 걷히는 범위를 조절한다.
        // .mixed(패스스루 위에만 표시)와 .full(완전 몰입)로도 전환할 수 있다.
        .immersionStyle(selection: $appModel.immersionStyle, in: .mixed, .progressive, .full)
    }
}
