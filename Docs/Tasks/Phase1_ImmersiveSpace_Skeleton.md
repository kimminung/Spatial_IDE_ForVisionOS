# Phase 1: ImmersiveSpace 초기 뼈대 코드 작성하기

> 상위 문서: [PRD_CodeSpace.md](../PRD_CodeSpace.md)
> 목표: 최소 런처 윈도우에서 진입하면 `ImmersiveSpace`가 열리고, 더미 코드 그래프가 Z축 깊이 레이아웃으로 공간에 배치되어 보이는 상태.

> **설계 변경 (실기기/시뮬레이터 검증 중 발견)**: 처음에는 `WindowGroup`을 완전히 없애고
> `UIApplicationPreferredDefaultSceneSessionRole`만으로 앱을 곧바로 `ImmersiveSpace`로 띄우려 했으나,
> 실행 시 `Fatal error: Your app was given a scene with scene session role
> UIWindowSceneSessionRoleApplication but no scenes declared in your app body match this role.`로 즉시 크래시했다.
> visionOS는 앱을 처음 연결할 때 항상 윈도우 역할의 씬을 요청하며, Apple HIG도
> "완전히 몰입형인 앱도 Shared Space에서 먼저 실행하는 것을 고려하라"고 명시한다.
> 그래서 진입 버튼만 있는 최소 `LauncherView`를 `WindowGroup`으로 유지하고,
> `openImmersiveSpace` 성공 시 그 윈도우를 스스로 닫아 이후에는 ImmersiveSpace만 남도록 했다.

---

## 완료 조건 (Definition of Done)

- [x] Apple Vision Pro 시뮬레이터 대상으로 빌드 성공
- [x] 앱 실행 시 크래시 없이 최소 런처 윈도우가 뜨고, "CodeSpace 진입" 버튼으로 ImmersiveSpace가 열림
- [x] ImmersiveSpace가 열리면 런처 윈도우는 자동으로 닫힘
- [x] 더미 그래프 노드(구체/큐브)가 X·Y·Z 좌표를 할당받아 공간에 배치됨
- [x] 호출 깊이가 깊을수록 노드가 Z축 안쪽(사용자에서 멀어지는 방향)에 놓임
- [x] 몰입 스타일 `.mixed` / `.full` 간 전환 가능한 상태값 존재 (UI 토글은 Phase 2)

---

## 태스크 목록

### T1. 프로젝트를 visionOS 전용으로 설정

- [x] `SUPPORTED_PLATFORMS` → `xros xrsimulator`
- [x] `TARGETED_DEVICE_FAMILY` → `7` (Apple Vision)
- [x] 활성 Run Destination → Apple Vision Pro 시뮬레이터 / 실기기 모두 확인
- [x] Info.plist `UIApplicationPreferredDefaultSceneSessionRole` = `UISceneSessionRoleImmersiveSpaceApplication`
  - 이 키가 있어야 `WindowGroup` 없이 앱 시작 시 ImmersiveSpace가 자동으로 열린다.
- [x] `PRODUCT_BUNDLE_IDENTIFIER` → `com.kimminung.SpatialIDEForVisionOS`
  - 템플릿이 생성한 placeholder 번들 ID(`devplaceholder.*`)는 실제 개발팀에 등록할 수 없어 실기기 서명이
    `Failed Registering Bundle Identifier`로 실패했다. 팀에 귀속 가능한 고유 번들 ID로 교체해 해결.
- [x] `INFOPLIST_KEY_UIApplicationSceneManifest_Generation` → `YES`
  - 런처 윈도우 + ImmersiveSpace(멀티 씬) 구조로 바꾼 뒤 실기기에서
    `[SwiftUI] Unable to open an immersive space when the app does not support multiple scenes.` 오류가 발생했다.
  - `UIApplicationSupportsMultipleScenes`는 최상위가 아니라 `UIApplicationSceneManifest` 딕셔너리 안에
    중첩되어야 하는 키라서 `AddInfoPlist`로는 올바르게 넣을 수 없었고, 이 빌드 설정으로 Xcode가
    직접 중첩 구조를 생성하도록 해 해결. 빌드 결과물의 Info.plist에서
    `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes = true`로 반영된 것을 확인.

### T2. 앱 엔트리 포인트 구성 (최소 런처 윈도우 + ImmersiveSpace)

- [x] `MyApp.swift`: `WindowGroup(id: "Launcher")` + `ImmersiveSpace(id:)` 두 씬 선언
- [x] `.immersionStyle(selection:in:)`으로 `.mixed`, `.full` 허용
- [x] `AppModel`(`@Observable`)을 두 씬 모두에 `.environment()`로 주입
- [x] `LauncherView`: "CodeSpace 진입" 버튼 → `openImmersiveSpace` 성공 시 `dismissWindow`로 자기 자신을 닫음
- [x] 템플릿의 빈 `ContentView.swift` 제거

### T3. 도메인 모델 정의

- [x] `CodeNodeKind`: `module`, `type`, `function`, `variable`
- [x] `CodeNode`: `id`, `name`, `kind`, `parentID` (Codable → Phase 4 JSON 로드 대비)
- [x] `CodeEdge`: `from`, `to`
- [x] `CodeGraph`: `nodes`, `edges` + `callDepths()` (BFS 기반 깊이 계산)

### T4. 더미 그래프 데이터

- [x] `CodeGraph.sample`: CodeSpace 자체 구조를 흉내낸 14개 노드, 15개 엣지
- [x] 루트(모듈) → 타입 → 함수 → 하위 함수 형태로 깊이 0~4 형성

### T5. Z축 깊이 레이아웃 알고리즘

- [x] `SpatialLayout.positions(for:)`: `[nodeID: SIMD3<Float>]` 반환
- [x] X: 같은 깊이의 노드를 중앙 정렬로 균등 분포
- [x] Y: 노드 종류별 오프셋 (module 위, variable 아래)
- [x] Z: `origin.z - depth * depthSpacing` (깊을수록 멀어짐)

### T6. RealityKit 엔티티 생성 및 RealityView 렌더링

- [x] `NodeEntityFactory.makeEntity(for:)`: kind별 메시(큐브/구체)와 `PhysicallyBasedMaterial`(약한 발광)
- [x] `CodeGraphSceneBuilder.makeRootEntity(graph:layout:)`: 루트 Entity 아래 노드 배치
- [x] `CodeSpaceImmersiveView`: `RealityView { content in content.add(root) }`

### T7. 검증

- [x] `BuildProject`로 시뮬레이터 대상 빌드 성공 확인
- [x] 콘솔 로그로 초기 "WindowGroup 없음" 구성이 즉시 크래시함을 확인 → `LauncherView` 추가로 해결
- [x] `BuildProject`로 실기기(김민웅님의 Apple Vision Pro) 대상 빌드 성공 확인
  - 최초 실패: placeholder 번들 ID 등록 불가 → 고유 번들 ID로 교체 후 해결
- [ ] 시뮬레이터/실기기 실행 후 런처 → "CodeSpace 진입" → 노드가 눈높이 앞 1.5m 부근에 보이는지 육안 확인 (사용자 확인 필요)

---

## 파일 구조 (Phase 1 결과)

```
Spatial_IDE_ForVisionOS/
├─ MyApp.swift                         # @main CodeSpaceApp — Launcher WindowGroup + ImmersiveSpace
├─ Models/
│  ├─ AppModel.swift                   # @Observable 앱 상태 (몰입 스타일, 그래프, 오픈 여부)
│  ├─ CodeGraph.swift                  # CodeNode / CodeEdge / CodeGraph + callDepths()
│  └─ CodeGraph+Sample.swift           # 더미 그래프 데이터
├─ Layout/
│  └─ SpatialLayout.swift              # Z축 깊이 레이아웃
├─ Rendering/
│  ├─ NodeEntityFactory.swift          # CodeNode → ModelEntity
│  └─ CodeGraphSceneBuilder.swift      # CodeGraph → 루트 Entity 트리
└─ Views/
   ├─ LauncherView.swift               # 최소 런처 윈도우 — 진입 버튼, 성공 시 자기 자신을 닫음
   └─ CodeSpaceImmersiveView.swift     # RealityView 컨테이너
```

---

## 설계 메모

- **깊이는 데이터가 아니라 계산값**: `CodeNode`에 depth를 저장하지 않고 `CodeGraph.callDepths()`가 엣지에서 BFS로 구한다. Phase 4에서 실제 AST JSON을 받을 때 레이아웃 로직을 그대로 재사용하기 위함.
- **Entity 이름 = 노드 ID**: `entity.name`에 `CodeNode.id`를 넣어 Phase 2(탭 → 어태치먼트), Phase 3(제스처 대상 식별)에서 역참조할 수 있게 한다.
- **머티리얼에 emissive 사용**: Phase 3의 Hover 발광 효과를 `emissiveIntensity` 조절만으로 구현할 수 있게 미리 `PhysicallyBasedMaterial`을 사용.
- **좌표계**: ImmersiveSpace 원점은 앱 실행 시 사용자 발밑. 루트 Entity를 `(0, 1.3, -1.5)`에 놓아 눈높이 앞에서 시작하도록 한다.
- **윈도우 없는 앱은 지원되지 않음**: `ImmersiveSpace` 하나만 선언한 앱은 visionOS의 초기 씬 연결(항상 윈도우 역할 요청)을 만족시키지 못해 즉시 크래시한다. 최소 1개의 `WindowGroup`이 필요하며, `LauncherView`가 그 역할을 최소한으로 수행하고 스스로 사라진다.

---

## 개정 — 디지털 크라운 몰입도 조절

- `AppModel.immersionStyle` 기본값을 `.mixed` → `.progressive(0.05...1.0, initialAmount: 0.35)`로 변경.
  `MyApp`의 `.immersionStyle(selection:in:)` 허용 목록에 `.progressive` 추가.
- 크라운을 돌리면 패스스루가 걷히는 포털 영역이 5%~100% 사이에서 커지고 작아진다. 그 영역에 보일
  배경으로 `ImmersiveBackdropFactory.makeSkyDome()`(반지름 30m, 안쪽 면만 그리는 어두운 남색 구체)을
  씬에 직접 추가했다. 그래프 루트의 자식이 아니므로 그래프를 조작해도 배경은 움직이지 않는다.
- `.onImmersionChange`로 현재 몰입도를 `AppModel.immersionAmount`(0~1)에 기록한다. 아직 UI에는 쓰지 않음.
- 참고: `.progressive`에서는 시스템 규칙에 따라 윈도우(런처)가 항상 3D 콘텐츠 앞에 그려진다.

## 개정 — 시스템 라이트/다크 외관 자동 적용

- 하드코딩 색을 모두 외관 의존 팔레트로 옮겼다. `Info.plist`에 `UIUserInterfaceStyle`을 강제하지
  않으므로 `colorScheme` 환경값은 시스템 설정을 그대로 따른다.
- **SwiftUI(카드)**: `CodePanelView`가 `@Environment(\.colorScheme)`를 읽어 토큰 색
  (`CodeTokenKind.color(for:)`), 노드 강조색(`CodeNodeKind.color(for:)`), 가독성 그림자(다크=어두운 그림자,
  라이트=밝은 헤일로)를 고른다. 식별자·구두점은 적응형 `.primary`.
- **RealityKit(돔·엣지)**: 머티리얼은 환경값을 자동으로 따르지 않으므로 `ScenePalette(scheme:)`로 색을
  만들고, `colorScheme`이 바뀌면 `CodeSpaceImmersiveView`의 `update` 클로저가
  `ImmersiveBackdropFactory.apply`와 `CodeGraphSceneBuilder.applyEmphasis(palette:)`로 다시 입힌다.
- 라이트 팔레트: 배경 옅은 회청색, 엣지 짙은 회색, 펄스 청록. 다크 팔레트: 짙은 남색 배경, 밝은 회색 엣지, 민트 펄스.

## 다음 Phase로 넘기는 항목

- 엣지(실린더) 렌더링 → Phase 2
- 몰입 스타일 전환 UI, 노드 탭 시 코드 패널 → Phase 2
- `InputTargetComponent` / `CollisionComponent` / `HoverEffectComponent` → Phase 3
