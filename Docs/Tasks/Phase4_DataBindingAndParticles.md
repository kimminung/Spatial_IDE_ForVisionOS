# Phase 4: 실제 데이터 바인딩 및 파티클 적용

> **2차 개정 — 엣지 흐름의 시각 언어 확장 (현재 구현)**
>
> 엣지에 의미(`CodeEdgeKind`)를 부여하고, 종류별로 색·방향·속도·감속이 다른 흐름을 그린다.
> 노드에는 브레이크포인트를 걸 수 있고, 카드 거터가 오류/종료 줄을 자동 표식한다. 그래프 아래에 범례를 둔다.
>
> | 종류 | 의미 | 선 | 펄스 | 머리 |
> | --- | --- | --- | --- | --- |
> | `owns` | 구조적 소유(모듈→타입, 타입→멤버) | 흐림(기본의 절반) | 작고 느림(0.15 m/s) | 없음 |
> | `calls` | 일반 호출 | 기본 | 기본 색, 0.45 m/s, 호출 방향 | 끝에 화살촉(원뿔) |
> | `throwsError` | 오류 전파 | 빨강 | 빨강, 0.70 m/s, **역방향**(호출된 쪽→호출한 쪽) | 출발 쪽에 뒤집힌 화살촉 |
> | `terminates` | fatalError/exit로 끝나는 경로 | 짙은 빨강 | 끝으로 갈수록 감속(ease-out)·축소·소멸 | 끝에 정지 막대 |
> | (일시정지) | 출발 노드에 브레이크포인트 | 빨강 | 출발점에 멈춰 약 1.4Hz 점멸 | — |
>
> - **데이터**: `CodeEdge.kind`(기본 `.calls`), `CodeNode.breakpointLines`. 둘 다 이전 JSON과 호환되도록
>   `decodeIfPresent`로 읽는다(`CodeGraph.swift`의 Codable 확장). 샘플/JSON에는 `load→parse`를 오류 전파,
>   `parse→validate`를 종료 경로로, `positions(for:)` 2번째 줄에 초기 브레이크포인트를 넣었다.
> - **브레이크포인트**: `AppModel.breakpoints`(그래프 데이터로 초기화, 거터 탭으로 토글). 브레이크포인트가 있는
>   노드에서 나가는 실행 엣지(`owns` 제외)는 `isPaused`로 표시된다. 실제 디버거와 연결된 것은 아니며,
>   "여기서 멈추면 어디까지 흐르는가"를 시각적으로 확인하는 정적 표식이다.
> - **카드 거터**: `throw/throws/try/catch` 줄엔 빨간 바, `fatalError/exit/abort/preconditionFailure/assertionFailure`
>   줄엔 정지 표식을 토큰에서 자동 검출. 거터 자체가 버튼이라 응시 하이라이트 후 핀치로 브레이크포인트를 토글한다.
> - **범례**: `FlowLegendView`가 그래프 하단 앵커(`LegendAnchor`)에 attachment로 붙는다.
> - 구현: `EdgeEntityFactory`(종류별 `flowSpeed`, `layoutPulse`, `setEmphasis(isPaused:)`),
>   `CodeGraphSceneBuilder.applyEmphasis(pausedNodeIDs:)`, `ScenePalette.lineColor/pulseColor(for:)`.
> - **엣지 끝점 = 선택 토큰 위치**: 선택이 없을 때(전체 흐름 보기) 엣지는 노드 중심을 잇는다. 토큰을
>   선택하면, 그 텍스트가 들어 있는 카드마다 첫 일치 토큰의 프레임을 `onGeometryChange`로 측정해
>   노드 중심 기준 미터 오프셋(`AppModel.tokenAnchors`)으로 보고하고, 흐름에 포함된 노드의 오프셋만
>   (`activeEdgeAnchors`) 엣지 끝점에 적용한다. 따라서 선택한 토큰에서 엣지가 출발하고, 상대 카드에
>   같은 이름(예: 선언부)이 있으면 그 토큰에 도착한다. `EdgeEndpointsComponent.startOffset/endOffset`을
>   지수 평활(τ≈1/12s)로 목표에 접근시켜 선택이 바뀔 때 엣지가 미끄러지듯 옮겨 붙는다.
>   포인트→미터 환산은 `SceneStyle.pointsPerMeter`(1360)를 쓴다.
> - **소유 체인 곡선(담김)**: 토큰을 선택하면 `AppModel.containmentNodeIDs`가 흐름에 포함된 노드와 그
>   조상(부모→…→루트)을 모은다. 이 집합의 노드로 들어오는 `owns` 엣지는 `EdgeEmphasis.containment`가 되어
>   직선을 숨기고, 세계 +Z(사용자 쪽)로 불룩한 2차 베지어 곡선(세그먼트 실린더 10개)으로 그려진다.
>   색은 `ScenePalette.containmentFlow`(짙은 파랑), 화살촉은 담는 쪽(`from`)을 향하고, 펄스도
>   담기는 쪽 → 담는 쪽으로 흐른다. 곡선의 불룩 방향은 컨테이너 로컬 프레임에서 세계 +Z를 가져와 현(弦)
>   성분을 제거해 구하므로, 그래프를 회전해도 항상 사용자 쪽으로 튀어나온다. 끝점 오프셋(토큰 위치)도
>   그대로 적용된다. 범례에 "담김" 항목 추가.
> - 후속 후보: 실제 런타임 로그(os_signpost)로 펄스를 실제 호출 순서대로 재생, 브레이크포인트 히트 시 카드 강조,
>   `await`(비동기 경계) 종류 추가.

> **개정 — 파티클 제거, 엣지 펄스로 대체**: "엣지 주위의 파티클 대신 엣지만으로 흐름을 표현"하라는
> 피드백에 따라 `ParticleEmitterComponent`를 제거했다. 엣지는 컨테이너 엔티티 아래 두 실린더
> (얇은 반투명 기본 선 + 굵고 밝은 짧은 펄스)로 구성되며, 펄스가 시작 노드→끝 노드 방향으로
> 일정 속도(0.45 m/s)로 반복 이동해 흐름을 나타낸다. `EdgeEntityFactory.advanceFlow`가 매 프레임
> `flowPhase`를 전진시킨다. 아래 T2의 파티클 관련 항목은 이력으로만 남긴다.

> 상위 문서: [PRD_CodeSpace.md](../PRD_CodeSpace.md)
> 목표: 하드코딩된 Swift 데이터 대신 JSON 리소스에서 그래프를 로드하고, 엣지를 따라 흐르는 파티클로
> 실행 흐름을 시각화한다.

---

## 완료 조건 (Definition of Done)

- [x] 앱이 `SampleGraph.json`(더미 AST JSON)을 읽어 그래프를 구성함
- [x] JSON 로드에 실패해도 앱이 크래시하지 않고 `CodeGraph.sample`로 안전하게 대체됨
- [x] 모든 엣지를 따라 빛 궤적 파티클이 흐름
- [x] 빌드 성공 및 리소스가 앱 번들에 포함됨을 확인

---

## 태스크 목록

### T1. JSON 데이터 파이프라인

- [x] `Resources/SampleGraph.json` 추가 — `CodeGraph.sample`과 동일한 구조·내용을 JSON으로 옮김
- [x] `Models/GraphLoader.swift` 신설
  - `loadBundledSample()`: 번들에서 `SampleGraph.json`을 찾아 디코딩
  - 리소스가 없거나 디코딩 실패 시 `Logger`로 에러를 남기고 `CodeGraph.sample`로 폴백
- [x] `AppModel.graph` 초기값을 `.sample` → `GraphLoader.loadBundledSample()`로 교체
- [x] 빌드 산출물(`Spatial_IDE_ForVisionOS.app/SampleGraph.json`)에 리소스가 실제로 포함됐는지 확인

### T2. 실행 흐름 파티클

- [x] `Rendering/EdgeEntityFactory.makeParticleTrail(edge:from:to:)` 신설
  - 엣지 시작 노드 위치에서 태어나 엣지 방향(로컬 +Y, 실린더와 동일한 회전)으로 진행
  - `lifeSpan = 엣지 길이 / speed`로 맞춰, 파티클이 대략 반대편 노드에 도달할 때 소멸하도록 근사
  - `ParticleEmitterComponent.mainEmitter.color`를 흰색 constant color로 설정해 "빛 궤적"처럼 보이게 함
- [x] `Rendering/CodeGraphSceneBuilder.makeRootEntity(...)`에 `includeParticles` 플래그 추가,
      `CodeSpaceImmersiveView`에서 `true`로 호출해 파티클 그룹(`EdgeParticles`)을 함께 생성
- [x] 파티클 엔티티도 `EdgeEndpointsComponent`를 가져, Phase 3의 `updateEdgeTransforms`가
      노드 드래그 시 파티클 궤적도 함께 갱신함

---

## 설계 메모 / 트러블슈팅

- **깊이 계산 로직 재사용 확인**: Phase 1에서 "깊이는 데이터가 아니라 계산값"으로 설계해 둔
  `CodeGraph.callDepths()`와 `SpatialLayout.positions(for:)`는 JSON에서 로드한 그래프에도
  수정 없이 그대로 재사용됐다 — 데이터 소스를 Swift 리터럴에서 JSON으로 바꿔도 레이아웃/렌더링
  파이프라인은 전혀 손대지 않았다.
- **파티클의 근사치**: 실제 실행 흐름(호출 순서·데이터 이동 시점)과 동기화된 파티클은 아니고,
  모든 엣지에서 상시 흐르는 장식적 이펙트에 가깝다. 실제 런타임 이벤트에 맞춰 파티클을
  트리거하려면 별도의 이벤트 버스(예: 특정 함수 호출 시 해당 엣지의 `birthRate`를 순간적으로
  올리는 방식)가 필요 — 향후 Phase로 분리 검토.
- **폴백 안전성**: `GraphLoader`가 어떤 이유로든 실패해도 앱은 항상 `CodeGraph.sample`을 보여준다.
  두 데이터가 동일한 내용을 담도록 유지해, 폴백이 발생해도 사용자가 차이를 느끼지 않게 했다.

---

## PRD 마일스톤 기준 남은 항목 (향후 작업 후보)

- SwiftSyntax로 실제 Swift 소스를 파싱해 `SampleGraph.json` 자리를 대체하는 실데이터 파이프라인
- 노드 100개 이상 규모에서의 성능 최적화 (엣지 인접 리스트 캐시 등, Phase 3 메모 참고)
- 실행 흐름 파티클을 실제 함수 호출 이벤트에 연동
