# Phase 2: 노드 연결 및 UI 어태치먼트

> 상위 문서: [PRD_CodeSpace.md](../PRD_CodeSpace.md)
> 목표: 노드 사이를 실린더 엣지로 연결하고, 노드를 탭하면 그 옆에 실제 코드가 담긴 2D 패널이 떠오른다.

---

## 완료 조건 (Definition of Done)

- [x] `CodeGraph.edges`에 정의된 모든 관계가 3D 실린더로 시각화됨
- [x] `CodeNode`에 코드 스니펫 필드가 추가되고, 더미 데이터에 실제 텍스트가 채워짐
- [x] 노드를 탭하면 그 노드 위치 옆에 코드 패널이 나타남
- [x] 같은 노드를 다시 탭하면 패널이 사라짐 (다른 노드를 탭하면 패널 내용이 전환됨)
- [x] 빌드 성공 (Apple Vision Pro 시뮬레이터/실기기)

---

## 태스크 목록

### T1. 코드 스니펫 데이터 모델

- [x] `CodeNode.codeSnippet: String?` 추가 (`Models/CodeGraph.swift`)
- [x] `CodeGraph.sample`의 14개 노드에 각각 짧은 Swift 스니펫 채움 (`Models/CodeGraph+Sample.swift`)

### T2. 엣지(실린더) 렌더링

- [x] `Rendering/EdgeEntityFactory.swift` 신설
  - `makeCylinder(edge:from:to:)`: `MeshResource.generateCylinder`로 얇은 반투명 실린더 생성
  - 실린더는 로컬 Y축이 높이축이므로 `simd_quatf(from:[0,1,0], to: direction)`으로 회전시켜 두 노드 방향에 맞춤
  - `EdgeEndpointsComponent`로 시작/끝 노드 ID를 엣지 엔티티에 보관 (Phase 3 드래그 대응용)
- [x] `Rendering/CodeGraphSceneBuilder.swift`: 루트 엔티티 아래에 `Nodes`/`Edges` 그룹을 나눠 추가

### T3. 노드 탭 → 코드 패널 어태치먼트

- [x] `Views/CodePanelView.swift`: 노드 이름/종류/코드 스니펫을 보여주는 SwiftUI 카드
- [x] `Views/CodeSpaceImmersiveView.swift`: `RealityView(make:update:attachments:)` + `Attachment(id:)`로
      노드별 패널을 선언하고, `AppModel.selectedNodeID`에 따라 `content.add`/`isEnabled` 토글
- [x] `AppModel.selectedNodeID` 추가 — 탭 상태를 앱 전역에서 관리

---

## 설계 메모 / 트러블슈팅

- **최종 형태 — 카드는 코드 텍스트만**: 접기/펼치기, 테두리, 배경, 헤더, 뒤판을 모두 없앴다.
  `CodeTokenizer`가 스니펫을 토큰으로 나누고, 카드는 줄별 `HStack`에 토큰 `Text`를 구문 강조 색으로
  그린다. 식별자/타입 토큰만 `Button` + `.hoverEffect()`로 응시·탭 대상이 된다. 가독성은 텍스트 그림자로
  확보한다. 조작 설계는 Phase 3 문서의 4차 개정 참고.

- **실기기 검증 후 설계 변경 — 코드 카드 상시 표시**: 처음에는 "탭한 노드에만" 패널을 띄웠는데,
  실기기에서 노드가 단순 도형으로만 보여 코드가 표현됐는지 확인할 수 없었다. Primitive처럼 모든 노드가
  코드 조각으로 보이도록, 기본 상태에서 스니펫 앞 4줄을 작은 카드로 항상 표시하고, 탭하면 전체 코드로
  확장하는 방식으로 바꿨다. 카드는 노드 엔티티의 **자식**으로 붙여 드래그·Magnify에 자동으로 따라간다.
- **탭 판정 버그 (단위 혼동)**: `DragGesture.Value.translation3D`는 뷰 로컬 좌표 **포인트** 단위인데
  미터 기준 임계값(0.02)과 비교해 탭이 사실상 항상 드래그로 판정되고 패널이 한 번도 열리지 않았다.
  `value.convert(_:from:to:)`로 시작점·현재점을 미터로 변환한 뒤 `simd_distance`로 비교하도록 수정.
  같은 수정에서 "드래그 시작 위치 + 변위"로 이동시켜, 핀치 순간 노드가 손 위치로 점프하던 문제도 없앴다.
- **노드 도형 제거 (Phase 3에서 완결)**: 이후 Phase 3 개정에서 노드의 큐브/구체 도형을 완전히
  없애고 코드 카드만 남겼다. 자세한 내용은 [Phase3_SpatialInteraction.md](Phase3_SpatialInteraction.md)의
  "개정 사항" 참고.

- **최신 visionOS SDK의 attachment API 변경**: `RealityView`의 `attachments` 빌더에서 평범한 SwiftUI
  `View`에 `.tag(_:)`를 붙이는 예전 방식은 `'init(make:update:attachments:)' is unavailable in visionOS:
  Use the Attachment type` 컴파일 오류가 났다. 대신 `Attachment(id:) { ... }`로 각 뷰를 감싸야 한다.
  `XcodeRefreshCodeIssuesInFile`로 바로 잡아냈다.
- **패널은 항상 한 번만 추가**: 모든 노드의 attachment 엔티티를 `update` 클로저에서 최초 한 번 `content.add`
  하고, 이후에는 `isEnabled`만 토글해 보이고 숨긴다. attachment를 매번 add/remove하면 불필요한 재생성 비용이 든다.
- **엣지는 입력 대상이 아님**: `InputTargetComponent`를 노드에만 부여했기 때문에, `.targetedToAnyEntity()`
  제스처는 엣지·파티클 엔티티를 절대 타깃으로 잡지 않는다. 별도의 필터링 로직이 필요 없다.

---

## 다음 Phase로 넘기는 항목

- 노드 드래그 이동, 전체 그래프 Magnify, 시선 Hover 발광 → Phase 3
- 실제 JSON 로드, 실행 흐름 파티클 → Phase 4
