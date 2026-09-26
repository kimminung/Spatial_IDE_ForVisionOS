# Phase 5: Z축 코드 접힘 (3축 코드 배열)

> 상위 문서: [PRD_CodeSpace.md](../PRD_CodeSpace.md)
> 목표: 코드 중 일부를 카드 평면(X·Y)에서 떼어 Z축으로 꺾어 배치한다. 정면에서 보면 평면 코드만
> 보이고, 그래프를 기울이면 접힌 코드가 드러나는 "3축 코드 배열"을 만든다.

---

## 무엇을 접는가 (설계 결정)

접을 후보를 검토한 결과, **"주 흐름은 평면에, 벗어나는 흐름은 Z축에"** 를 원칙으로 세웠다.

| 우선순위 | 후보 | 이유 | 상태 |
| --- | --- | --- | --- |
| 1 | `catch` 블록 본문, `guard … else` 본문 | 예외·조기 탈출 경로. 평소엔 읽지 않고, 정상 흐름을 가리기만 한다. 이미 빨간 엣지(오류 전파/종료)와 의미가 이어진다. | **이번 구현** |
| 2 | 클로저·`Task { }`·`async` 연속 본문 | 비동기 경계 — 실행 시점이 다른 코드를 다른 깊이에 두면 직관적 | 후속 |
| 3 | `switch`의 각 `case` 본문 | 분기를 깊이 방향으로 쌓아 "여러 갈래"를 표현 | 후속 |
| 4 | 주석·attribute(`@…`) | 메타 정보를 사용자 쪽(+Z)으로 살짝 띄우는 방식 | 후속·검토 |
| — | 주 흐름 토큰(선언, 호출, 반환) | 응시·선택·엣지 앵커의 대상이라 평면에 남아야 한다 | 접지 않음 |

---

## 완료 조건 (Definition of Done)

- [x] `catch` 블록과 `guard … else` 본문이 카드 평면에서 사라지고, 헤더 줄 끝에 힌지 표식(↳ N)이 남는다
- [x] 접힌 본문이 헤더 줄 왼쪽 아래 모서리를 축으로 Y축 78° 회전해 카드 뒤(-Z)로 뻗어 붙는다
- [x] 접힌 본문 안의 토큰 선택·거터(브레이크포인트) 동작이 카드와 동일하다
- [x] 범례에 "접힘(Z축)" 항목 추가
- [x] 빌드 성공, 샘플 그래프에서 `GraphLoader.load`(catch)·`GraphLoader.validate`(guard-else) 2곳이 접힌다

---

## 태스크 목록

### T1. 접힘 영역 검출 — `Models/CodeFolder.swift`

- [x] `CodeFoldRegion { kind(.catchBlock/.guardElse), headerLine, bodyLines }`
- [x] `CodeFolder.regions(in:)`: 줄의 마지막 유효 토큰이 `{`이고 키워드에 `catch` 또는 `guard`+`else`가 있으면
      헤더로 본다. 이후 줄에서 구두점 `{`/`}`로 깊이를 세어 짝이 되는 `}` 줄을 찾고, 헤더 다음 줄부터
      그 직전까지를 본문으로 한다. 문자열·주석은 토크나이저가 한 토큰으로 묶어 두므로 내부 중괄호는 세지 않는다.
- [x] 닫는 줄이 곧 다음 헤더일 수 있어(`} catch {`) 닫는 줄부터 다시 검사한다. 중첩은 바깥 것만 접는다.
- [x] `bodyLines(of:in:)`: 헤더 들여쓰기만큼 앞 공백을 걷어내 접힌 평면이 한 단계 들여쓰기에서 시작한다.
- [x] `RunCodeSnippet`으로 샘플 검증: `load` → catch 본문 `return .sample` 1줄, `validate` → else 본문 `fatalError(…)` 1줄.

### T2. 카드 렌더링 분리 — `Views/CodeLinesView.swift`, `Views/CodePanelView.swift`

- [x] 줄/거터/토큰 렌더링을 `CodeLinesView`로 추출(카드와 접힌 블록이 공유)
- [x] `CodePanelView`는 접힌 본문 줄을 제외한 `visibleLines`만 그린다. 엣지 앵커 토큰 검색도 보이는 줄로 한정.
- [x] 헤더 줄 끝에 힌지 글리프(`arrow.turn.down.right` + 접힌 줄 수). 색은 접힘 종류별
      (`ScenePalette.foldHinge(for:)`: catch → 오류 빨강, guard-else → 종료 짙은 빨강)
- [x] 헤더 줄 프레임을 `onGeometryChange`로 측정 → 왼쪽 아래 모서리를 노드 중심 기준 미터 오프셋으로 환산해
      `onFoldHingeChange([regionID: SIMD3<Float>])`로 보고

### T3. 접힌 블록 배치 — `Views/FoldedBlockView.swift`, `Views/CodeSpaceImmersiveView.swift`

- [x] `FoldedBlockView`: 왼쪽에 2pt 힌지 바 + `CodeLinesView`. 렌더링 크기를 `onSizeChange`로 보고.
- [x] 접힘 영역마다 별도 `Attachment(id: "\(nodeID)#fold\(regionID)")` 생성(SwiftUI attachment는 평면 하나라
      블록마다 따로 떼어야 회전할 수 있다)
- [x] `make`: 노드 엔티티 아래에 피벗 엔티티(이름 = attachment ID, `orientation = quat(78°, Y축)`)를 두고 그 자식으로
      attachment 부착
- [x] `update`: `placeFoldedBlocks` — 피벗 위치 = 힌지 오프셋, attachment 위치 = 피벗 로컬 (+w/2, −h/2, 0)
      (attachment는 중심 기준이므로 왼쪽 위 모서리를 힌지에 맞춘다). Y축 +78° 회전이면 로컬 +X가 세계 −Z 쪽으로
      가므로 본문이 카드 **뒤**로 뻗는다.
- [x] 접힌 블록에도 `graphGestures` 적용(블록을 보고 핀치해도 전역 확대·회전이 계속 동작)

### T4. 스타일·범례·문서

- [x] `SceneStyle.foldAngle = 78°` — 90°가 아닌 이유: 정면에서도 얇은 띠가 남아 "여기 접혀 있다"는 단서가 된다
- [x] `FlowLegendView`에 "접힘(Z축)" 항목
- [x] PRD 마일스톤 표에 Phase 5 추가

---

## 설계 메모 / 트러블슈팅

- **접는 방향(−Z, 카드 뒤)**: "밀어 두는" 의미와 맞고, 앞쪽 노드 레이어(깊이 간격 0.5 m)와 겹치지 않는다.
  블록 폭은 대개 200pt 이하 → 약 0.15 m 깊이. 반대로 사용자 쪽(+Z)으로 꺾고 싶으면 `foldAngle` 부호만 바꾸면 된다.
- **힌지 위치**: 카드 왼쪽 가장자리(거터 포함) 기준이다. 본문 들여쓰기를 헤더 기준으로 걷어냈으므로 접힌 평면은
  "거터 + 한 단계 들여쓰기 + 본문"으로 시작한다. 헤더의 `{` 위치를 힌지로 쓰는 안도 검토했으나, 거터가
  평면 밖으로 튀어나가 브레이크포인트 표식이 어색해져 채택하지 않았다.
- **엣지 앵커와의 관계**: 접힌 본문 안의 토큰을 선택하면 쓰임새 흐름 강조는 정상 동작하지만, 엣지 끝점은
  회전된 평면 안의 토큰 위치를 알 수 없어 노드 중심(또는 카드 평면의 같은 이름 토큰)에 붙는다. 회전 변환을
  반영한 앵커 보고는 후속 과제.
- **왜 attachment 하나로 못 접는가**: `ViewAttachmentEntity`는 SwiftUI 뷰 하나를 평면 한 장으로 렌더링한다.
  뷰 일부만 3D 회전할 수 없으므로 접힘 단위마다 attachment를 나눈다. 대신 카드와 블록 사이 상태(선택·브레이크포인트·
  흐림)는 같은 `AppModel` 값을 읽어 항상 일치한다.
- **실기기 확인 항목**: (1) 힌지 y 정렬 — 카드 줄 간격 2pt와 `pointsPerMeter` 1360이 실제 렌더 크기와 맞는지,
  (2) 78°에서 정면 띠의 가시성이 적당한지(너무 두꺼우면 82~85°), (3) 라이트 모드에서 접힌 블록 텍스트 대비.

---

## 후속 후보

- 2·3순위(클로저/`Task`/`async` 본문, `switch` case 스택) 접기 — `CodeFolder.headerKind`에 규칙만 추가하면 된다
- 접힌 블록 안 토큰의 엣지 앵커(피벗 회전·오프셋을 곱해 노드 로컬 좌표로 환산)
- 접힌 블록 응시 시 잠시 펼치기(hover는 시스템 전용이라 핀치로 토글하는 방식이 현실적)
