# Phase 6: 대규모 코드베이스 대응 아키텍처

> 상위 문서: [PRD_CodeSpace.md](../PRD_CodeSpace.md)
> 배경: "10만 줄 이상을 관리하는 조직에서도 쓸 만한가"라는 질문에 대한 답. Phase 1~5의 인터랙션 언어
> (토큰 선택, 의미별 엣지 흐름, 담김 곡선, Z축 접힘)는 유지하고, 그 아래를 세 가지로 교체했다:
> **실데이터 인덱서**, **포커스 기반 표시(시맨틱 줌)**, **배치 렌더링**. 여기에 탐색 수단(검색)을 더했다.

---

## 진단 (변경 전)

| 문제 | 왜 대규모에서 깨지나 |
| --- | --- |
| 모든 노드에 코드 카드 attachment 상시 표시 | attachment 하나가 토큰마다 버튼·hover를 가진 SwiftUI 계층. 수십 장이 상한 |
| 엣지마다 엔티티 3~16개, 매 프레임 전부 순회 | 엣지 수천 개면 90 fps 불가 |
| 호버 흐름이 이름 문자열 일치 | `data`, `count`, `id` 같은 이름이 수백 곳 → 오탐으로 흐름이 무의미 |
| 손으로 쓴 더미 JSON | 실제 코드가 없으니 "파악"을 검증할 수 없음 |
| 인덱스 순서 X 나열 레이아웃, 탐색 수단 없음 | 노드가 늘면 벽. 검색·점프 없이는 길을 잃음 |

---

## 완료 조건 (Definition of Done)

- [x] 인덱서가 실제 Swift 소스 트리를 파싱해 v2 그래프 JSON을 만들고, 앱이 그것을 우선 로드한다
- [x] 이 프로젝트 자체 소스(26 파일)를 인덱싱한 `CodeSpaceGraph.json`(노드 392, 엣지 531)이 번들에 포함된다
- [x] 토큰 선택이 문자열 일치가 아니라 심볼 참조표로 선언·참조 노드를 찾는다(v1 샘플은 폴백)
- [x] 컨테이너는 칩으로 접혀 있고, 펼친 것만 카드가 된다. 카드 수가 예산(16)을 넘으면 오래된 펼침부터 자동으로 접힌다
- [x] 포커스 밖 관계는 `LowLevelMesh` 라인 메시 하나로 그린다(엣지 수와 무관하게 드로우 콜 ≤ 3)
- [x] 심볼 검색 → 그 자리까지 펼치고 흐름 강조
- [x] 빌드 성공, 스니펫 실행으로 포커스·예산·심볼 해석·검색 동작 확인

---

## 태스크 목록

### T1. 빌드 타임 인덱서 — `Tools/CodeSpaceIndexer` (Swift 패키지, SwiftSyntax 601)

- [x] `DeclarationCollector`(SyntaxVisitor): struct/class/enum/actor/protocol → `type`, func/init → `function`,
      타입·모듈 수준 var/let → `variable`. `extension Foo`는 별도 노드 없이 `Foo`에 멤버를 합친다
      (다른 모듈 타입의 확장은 `Module.Foo` 타입 노드를 만들어 준다).
- [x] 노드 ID = `모듈.타입경로.이름(라벨:)` — 파일·순서와 무관한 안정 식별자. 오버로드는 `#2` 접미.
- [x] 스니펫: 함수는 본문 전체(공통 들여쓰기 제거, 30줄 초과 시 중간 생략), 타입은 헤더 + 저장 프로퍼티 한 줄 요약
      + "함수 N개" 주석(계산 프로퍼티는 `{ … }`로 중괄호 균형 유지 — 접힘 검출이 중괄호를 센다).
- [x] `ReferenceCollector`: 본문의 호출(`foo()`, `bar.foo()`), 값(`bar.foo`), 타입(`Foo`) 참조와 `try` 여부.
- [x] `SymbolResolver`: base가 타입 이름 → 그 타입 멤버, base가 같은 타입의 프로퍼티(타입 주석 있음) → 그 타입 멤버,
      base 없음 → 같은 타입 → 모듈 수준, 마지막으로 모듈 전체에서 **유일**할 때만. base 없는 값 참조는
      지역 변수일 수 있어 유일성 폴백을 하지 않는다(`graph`가 `AppModel.graph`로 붙던 오탐 수정).
- [x] 엣지 종류: 피호출자 본문에 `fatalError/exit/…` → `terminates`, 피호출자가 `throws`이고 `try` 안 → `throwsError`, 그 외 `calls`.
      같은 (from,to)는 terminates > throwsError > calls 우선.
- [x] 출력: `schemaVersion 2`, 노드마다 `file`, `line`, `symbolRefs: [식별자: 노드ID]`.

```sh
cd Tools/CodeSpaceIndexer
swift run codespace-indexer ../../Spatial_IDE_ForVisionOS --module CodeSpace \
  -o ../../Spatial_IDE_ForVisionOS/Resources/CodeSpaceGraph.json
```

결과(이 프로젝트, Phase 6 코드 포함 최종): 파일 26 → 노드 392, 엣지 531(호출 계열 140). Phase 6 착수 시점(22 파일)에는
노드 291(타입 44, 함수 75, 변수 171), 엣지 376(owns 290, calls 85, throwsError 1)이었고 아래 검증 표는 그 그래프 기준이다.

### T2. 스키마 v2 + 심볼 기반 흐름 — `CodeGraph.swift`, `GraphIndex.swift`, `UsageFlow.swift`, `GraphLoader.swift`

- [x] `CodeNode.file/line/symbolRefs` (`decodeIfPresent`로 v1 호환)
- [x] `GraphIndex`: 노드 사전, 부모→자식(선언 줄 순), 나가는/들어오는 엣지, **심볼 → 참조 노드** 역색인. 그래프가 바뀔 때만 생성.
- [x] `UsageFlow.relatedNodeIDs`: `symbolRefs[토큰]` → 선언 노드 + 그 심볼을 참조하는 노드. 심볼표가 있는데 해석되지 않은
      토큰(지역 변수, 외부 프레임워크)은 자기 노드만. 심볼표가 없는 v1 데이터만 이름 일치로 폴백.
- [x] `GraphLoader.loadBundledGraph()`: `CodeSpaceGraph.json` → `SampleGraph.json` → `CodeGraph.sample`.

### T3. 포커스 모델(시맨틱 줌) + 계층 레이아웃 — `AppModel.swift`, `SpatialLayout.swift`

- [x] `expandedIDs`: 펼친 컨테이너. 처음엔 루트(모듈)만 → 최상위 타입 44개가 **칩**으로 보인다.
- [x] `visibleNodes`: 루트에서 펼친 컨테이너를 따라 내려간 집합. `isCard` = 잎이거나 펼친 컨테이너.
- [x] `cardBudget = 16`: `expand` 후 카드 수가 넘으면 `expansionOrder` 앞(오래된 것)부터 `collapse`. 새로 펼친 것과 그 조상은 보호.
- [x] `reveal(id)`: 조상을 모두 펼침. `toggleSelection`은 선택 토큰이 가리키는 선언이 접혀 있으면 자동으로 `reveal`한다
      ("흐름의 목적지가 보이게").
- [x] `edgeSets`: 양 끝이 보이는 엣지는 **포커스 엣지**(리치 엔티티; `owns`는 자식이 카드일 때만), 한쪽이라도 접혀 있으면
      끝점을 가장 가까운 보이는 조상으로 치환해 **컨텍스트 엣지**(가중치 = 묶인 원본 수)로 집계.
- [x] `SpatialLayout.positions(visible:index:expanded:sizes:isCard:)`: 컨테이너 아래에 자식들을 실제 렌더링 크기로 줄을 채워
      배치(flow packing, 줄 폭 3.0 m), 자식 군집은 부모보다 0.35 m 뒤. 펼친 컨테이너는 "카드 + 자식 블록"을 한 덩어리로
      취급해 형제와 겹치지 않는다. 결과는 루트가 (0,0,0)인 로컬 좌표.
- [x] 카드·칩이 `onGeometryChange`로 크기를 보고(`AppModel.cardSizes`) → 레이아웃이 다시 계산되고 노드가 0.25 s 동안 미끄러져 이동.

### T4. 증분 씬 갱신 + 배치 라인 메시 — `GraphSceneController.swift`, `ContextEdgeMesh.swift`

- [x] `CodeGraphSceneBuilder`(전체 1회 생성) 삭제 → `GraphSceneController.sync(...)`: 새로 보이는 노드·엣지만 생성, 사라진 것만 제거,
      나머지는 `move(to:)`로 위치만 갱신. 첫 sync의 경계 상자 중심을 피벗으로 잡아 루트 원점(확대·회전 축)이 그래프 중심에 온다.
- [x] attachment는 `attachments.entity(for:)`로 노드 엔티티에 붙이고, 부모가 다르면 다시 붙인다. 카드 노드의 접힘 블록 피벗도 여기서 관리.
- [x] `ContextEdgeMesh`: `LowLevelMesh`(float3 정점, `.line` 토폴로지) 하나에 모든 컨텍스트 선분을 채우고, 가중치 구간
      (1 / 2~4 / 5+)별로 파트 3개 → `UnlitMaterial` 불투명도 0.14 / 0.30 / 0.55. 정점 용량은 2배씩 늘리고 보이는 집합이 바뀔 때만 갱신.
- [x] `tick`은 포커스 엣지(수십 개)만 순회. 컨텍스트 메시는 매 프레임 비용 0.

### T5. 칩·검색·컨테이너 접기 — `NodeChipView.swift`, `SearchPanelView.swift`, `CodePanelView.swift`

- [x] `NodeChipView`: 종류 아이콘 + 이름 + 자손 수. 캡슐 배경(코드가 아닌 구조 표식이라 카드와 구분). 탭 → 펼침.
      선택 토큰의 흐름이 칩 안쪽에 닿으면 테두리로 알린다(흐리게 하지 않음).
- [x] `SearchPanelView`(그래프 위 앵커): TextField 검색 → 결과 탭 → `AppModel.focus(on:)` = reveal + 이름 토큰 선택.
      우측에 "카드 N/16" 예산 표시.
- [x] 펼친 컨테이너 카드 위에 작은 "타입 접기/모듈 접기" 버튼(`onCollapse`). 코드 카드의 테두리·배경 없음 원칙은 유지.

---

## 검증 (스니펫 실행, 인덱스 그래프 기준)

| 상태 | 보이는 노드 | 카드 | 칩 | 포커스 엣지 | 컨텍스트 엣지 |
| --- | --- | --- | --- | --- | --- |
| 초기(모듈만 펼침) | 39 | 3 | 36 | 2 | 20 (최대 가중치 6) |
| `AppModel` 펼침 | 57 | 22 | 35 | 21 | 22 |
| 이어서 `EdgeEntityFactory` 펼침 | 66 | 31 → 예산 초과로 `AppModel` 자동 접힘 | | 50 | 23 |

- `loadBundledSample()` 안의 `parse` 선택 → `GraphLoader.parse(data:)`로 해석, 관련 노드 2개(오탐 0). 선택 시 `GraphLoader`가 자동으로 펼쳐짐.
- `update(...)` 안의 `geometry` 선택 → 선언 + 참조 노드 2개(`layoutCurve`, `update`).
- "palette" 검색 → 12개(변수 `palette` 4곳은 컨테이너 이름으로 구분).

---

## 설계 메모 / 한계

- **인덱서의 이름 해석은 근사치다.** 타입 정보 없이 이름·스코프로 해석하므로 `appModel.toggleSelection(...)`처럼
  프로퍼티에 타입 주석이 없으면(`@Environment(AppModel.self) var appModel`) 모듈 전체 유일성에 의존한다.
  완전한 해석은 **IndexStoreDB(USR)** 연동으로 대체해야 한다. 노드 ID 형식은 그때도 유지된다.
- **모듈이 하나다.** 멀티 모듈·모노레포는 `--module`을 달리해 여러 번 돌리고 JSON을 합치면 되지만, 모듈 간 참조 해석은 USR 없이는 어렵다.
- **레이아웃은 아래로 자란다.** 큰 타입을 펼치면 카드가 눈높이 아래로 내려간다. 줄 폭 3 m와 예산 16으로 완화했고,
  한 손 드래그로 그래프를 끌어올릴 수 있다. 다음 단계는 사용자가 옮긴 위치를 저장하는 것(공간 기억).
- **컨텍스트 선은 1 px 라인**이다(`.line` 토폴로지). 두께가 필요하면 선분마다 사각형 4정점으로 바꾸면 되고, 구조는 그대로다.
- **엣지 앵커·접힘**은 카드 노드에서만 동작한다(칩은 중심). 이전 Phase의 동작은 카드 안에서 그대로 유지된다.
- 초기 카드 3장 중 하나는 다른 모듈 타입의 확장(`extension View`)처럼 자식이 없는 타입 노드다. 인덱서에서 확장 전용 타입을
  칩으로 남길지(자식 0이면 카드가 됨) 정책을 정해야 한다.

---

## 후속 (P1 / P2)

- **P1** IndexStoreDB 기반 USR 해석, 멀티 모듈 병합, git diff 기반 "이번 변경만" 필터, 영향 범위(호출자/피호출자 깊이 슬라이더) 보기
- **P1** 사용자가 옮긴 노드 위치·펼침 상태·브레이크포인트 영속화(세션 간 공간 기억)
- **P2** os_signpost 트레이스로 실제 실행 순서대로 펄스 재생, SharePlay 코드 리뷰, attachment 안 Dynamic Type/VoiceOver 점검,
  장시간 사용을 위한 텍스트 크기·거리 재검토
