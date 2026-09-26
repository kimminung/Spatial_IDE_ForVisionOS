# Phase 3: 공간 인터랙션 적용

> 상위 문서: [PRD_CodeSpace.md](../PRD_CodeSpace.md)
> 목표: 노드를 손으로 잡아 이동시키고, 두 손으로 전체 그래프를 확대/축소·회전하며, 시선이 머무는 노드가 발광한다.

> **4차 개정 (현재 구현) — 손잡이 전면 제거, 토큰 단위 상호작용, 쓰임새 흐름 강조**
>
> | 하고 싶은 것 | 조작 | 구현 |
> | --- | --- | --- |
> | 식별자 응시 | 카드 안 변수/타입/함수 이름을 바라봄 → 시스템 Hover 하이라이트 | 토큰별 `Button` + `.hoverEffect()` (`CodePanelView`) |
> | 쓰임새 흐름 보기 | 하이라이트된 토큰을 핀치(탭) | `AppModel.selectedToken` → `UsageFlow.relatedNodeIDs` → 관련 노드/엣지만 밝게, 나머지 흐리게 |
> | 그래프 확대/축소 | 어디를 보든 두 손 핀치 후 벌리기/모으기 | `GraphGestureController` (비타기팅 `MagnifyGesture`) |
> | 그래프 회전 | 어디를 보든 두 손 핀치 후 돌리기 | `RotateGesture3D(constrainedToAxis: nil)` — 축 제한 없는 자유 회전 |
> | 그래프 이동 | 어디를 보든 한 손 핀치 후 끌기 | 비타기팅 `DragGesture(coordinateSpace: .immersiveSpace)` |
>
> - **플랫폼 제약**: visionOS는 개인정보 보호를 위해 시선(호버) 위치를 앱에 전달하지 않는다. 앱이 할 수
>   있는 것은 토큰에 시스템 Hover 효과를 붙이는 것까지이며, "호버된 토큰 기준으로 흐름 표시"는 그 토큰을
>   핀치했을 때 동작한다.
> - **시선 자유**: 노드 손잡이·그래프 손잡이·카드 뒤판을 모두 없앴다. 대신 그래프 뒤에 보이지 않는
>   넓은 입력 판(`InputBackdrop`: Collision + InputTarget, 메시 없음)을 두어 빈 공간을 보고 핀치해도
>   입력이 `RealityView`로 전달되게 했고, 같은 제스처를 각 카드(attachment)에도 붙여 카드를 보고 있을
>   때도 동작한다.
> - **모드 잠금**: 이전에 "두 손 핀치가 확대와 회전에 동시에 반응"했던 문제는, 임계값(배율 6%, 회전 6°)을
>   먼저 넘은 제스처만 활성화하고 끝날 때까지 다른 제스처를 무시하는 `GraphGestureController.mode`로 해결했다.
> - **회전 피벗과 자유 회전 (4차 개정 보완)**: 처음엔 루트를 `layout.origin`(깊이 0 레이어 = main 노드
>   위치)에 두어 그 노드를 축으로 그래프가 휘둘렸고, 회전도 세로축으로 제한했었다. 지금은 루트를
>   모든 노드의 경계 상자 중심에 두어 그래프가 자기 중심으로 돌고, 축 제한을 풀어 모든 방향으로 회전한다.
>   SwiftUI 3D 좌표계(+y 아래)와 RealityKit(+y 위)은 Y축 반사 관계라, 제스처 회전 쿼터니언의 허수부
>   (ix, iy, iz)를 (-ix, iy, -iz)로 바꿔 넘긴다(`GraphGestureController.realityKitQuaternion`).
>   실기기에서 X/Z축 회전 방향이 손과 반대로 느껴지면 이 부호 변환만 제거하면 된다.
> - **노드 이동 제거**: 개별 노드 드래그는 토큰 탭과 충돌하므로 이번 개정에서 제외했다. 필요해지면
>   토큰이 아닌 빈 여백을 끄는 방식으로 재도입을 검토한다.
> - 카드는 배경·테두리·헤더 없이 구문 강조된 코드 텍스트만 있다(`CodeTokenizer`).

> **3차 개정 (현재 구현) — 손잡이 바 제거, 카드 자체를 잡는다**
> 2차 개정의 노드별 손잡이 바는 "바를 반드시 응시해야 해서 번거롭다"는 피드백을 받았다. 이제 카드
> 뒤에 카드 크기의 얇은 반투명 판(backing plate)을 두고, 그 판이 응시 하이라이트와 조작 히트 영역을
> 담당한다. 카드 어디를 보고 핀치-드래그해도 노드가 움직인다(`ManipulationComponent.HitTarget` →
> 노드). 카드는 테두리·배경·접기 버튼 없이 전체 코드를 항상 펼쳐 보이며, 접기/펼치기 상태
> (`selectedNodeID`)는 삭제했다. 카드 크기는 SwiftUI `onGeometryChange`로 측정해 `AppModel.cardSizes`에
> 넣고, `update` 클로저가 판 메시·히트 영역을 그 크기에 맞춘다(포인트→미터: 1360pt/m).
> 그래프 전체 손잡이(하단 막대)는 그대로 유지한다.
>
> 엣지는 조작 이벤트가 아니라 `SceneEvents.Update`(매 프레임)에서 노드 위치에 동기화하므로
> 핀치 중·관성 이동 중에도 항상 노드에 붙어 있다. 메시 재생성 대신 단위 실린더의 Y 스케일만 바꾼다.
> 파티클은 제거하고, 엣지 위를 흐르는 밝은 펄스 구간으로 흐름을 표현한다(Phase 4 문서 참고).
>
> 후속: 코드 텍스트는 SwiftUI로 남겨 두었으므로, 변수/인스턴스 토큰 단위 상호작용을 붙일 때는
> 토큰에 `Button`/제스처를 달고, 판의 히트 영역이 이를 가리지 않도록 판을 카드 뒤로만 한정하는
> 조정이 필요하다.

> **2차 개정 (현재 구현) — 커스텀 제스처 전면 제거, visionOS 표준 조작으로 통일**
> 1차 개정(보이지 않는 히트박스 + 직접 구현한 Drag/Magnify/Rotate)은 실기기에서 "어디를 핀치해야
> 하는지 알 수 없고, 두 손 핀치가 확대와 회전에 동시에 반응하며, 탭과 드래그가 뒤섞인다"는 UX 문제를
> 낳았다. 그래서 Apple HIG와 일반 visionOS 앱의 관습대로 다시 설계했다:
>
> | 하고 싶은 것 | 조작 | 구현 |
> | --- | --- | --- |
> | 코드 펼치기/접기 | 카드를 **응시 + 핀치(탭)** — 버튼과 동일 | `CodePanelView`가 SwiftUI `Button`, `.hoverEffect()` |
> | 노드 이동 | 카드 아래 **손잡이**를 응시 + 핀치-드래그 — 윈도우 바와 동일 | 손잡이에 `HitTarget` → 노드의 `ManipulationComponent` |
> | 그래프 이동 | 그래프 하단 큰 손잡이를 한 손으로 핀치-드래그 | 루트의 `ManipulationComponent` |
> | 그래프 확대/축소 | 그 손잡이를 두 손으로 핀치 후 벌리기/모으기 | 시스템 제공 |
> | 그래프 회전 | 그 손잡이를 두 손으로 핀치 후 원 그리기 | 시스템 제공 |
>
> 관성, 손 사이 핸드오프, 오디오 피드백, 응시 하이라이트는 모두 시스템이 제공하며 앱 코드에
> 제스처 인식 로직이 전혀 없다. 아래 "1차 개정" 절은 이력으로 남긴다.

---

## 완료 조건 (Definition of Done) — 2차 개정 기준

- [x] 카드를 응시하면 Hover 하이라이트, 핀치하면 접힘/펼침 전환 (버튼과 동일한 조작)
- [x] 카드 아래 손잡이를 응시 + 핀치-드래그하면 노드가 이동하고, 연결된 엣지·파티클이 함께 따라옴
      (손을 놓은 뒤 관성으로 미끄러지는 동안에도)
- [x] 그래프 하단 손잡이를 한 손으로 끌면 그래프 전체가 이동
- [x] 같은 손잡이를 두 손으로 조작하면 확대/축소·회전 (시스템 표준 두 손 제스처)
- [x] 조작 후 손을 놓으면 그 자리에 머무름 (`releaseBehavior = .stay`)
- [x] 빌드 성공

### 구현 파일

- `Rendering/NodeEntityFactory.swift`: `makeGrabHandle(redirectingTo:width:)` — 손잡이 메시 +
  `CollisionComponent`/`InputTargetComponent`/`HoverEffectComponent` + `ManipulationComponent.HitTarget`
- `Rendering/CodeGraphSceneBuilder.swift`: 루트에 `ManipulationComponent` + 그래프 손잡이(`GraphHandle`) 추가
- `Views/CodePanelView.swift`: `Button` + `.hoverEffect()`, 펼침 상태 표시용 chevron
- `Views/CodeSpaceImmersiveView.swift`: 커스텀 제스처 전부 삭제. `ManipulationEvents.DidUpdateTransform`/
  `WillEnd` 구독으로 엣지 갱신, 카드 펼침 상태에 따라 손잡이 높이 조정

---

## 1차 개정 당시의 완료 조건 (이력)

- [x] 노드를 잡아 드래그하면 그 노드가 이동하고, 연결된 엣지가 함께 따라옴
- [x] 같은 위치에서 손을 떼면(=거의 이동하지 않으면) 탭으로 인식되어 Phase 2의 코드 카드가 펼쳐짐/접힘
- [x] 두 손으로 Magnify(핀치)하면, 특정 엔티티를 바라보고 있지 않아도 그래프 전체 크기가 조절됨
- [x] 두 손으로 회전(핀치 후 원을 그리는 동작)하면, 특정 엔티티를 바라보고 있지 않아도 그래프 전체가
      다방면으로 회전함
- [x] 확대/축소·회전은 그래프의 시각적 중심을 기준으로 일어나, Y축으로 솟아오르거나 미끄러지지 않음
- [x] ~~노드를 응시하면 시스템 Hover 효과(발광)가 나타남~~ → 노드 도형 제거로 더 이상 해당 없음 (아래 개정 사항 참고)
- [x] 빌드 성공

---

## 태스크 목록

### T1. Hover 발광 피드백 (~~도입~~ → 개정에서 제거, 아래 참고)

- [x] ~~`HoverEffectComponent(.highlight(...))` 부여~~ — 노드에 눈에 보이는 도형이 없어져
      더 이상 하이라이트를 그릴 대상이 없으므로 제거했다. `CollisionComponent` + `InputTargetComponent`는
      탭/드래그 입력을 위해 유지한다. (자세한 내용은 "개정 사항" 참고)

### T2. 노드 드래그 + 탭 통합 제스처

- [x] `Views/CodeSpaceImmersiveView.swift`: `DragGesture(minimumDistance: 0).targetedToAnyEntity()`
      하나로 탭과 드래그를 함께 처리
  - `onChanged`: `value.convert(value.location3D, from: .local, to: parent)`로 노드 위치 갱신
  - `onChanged` 직후 `CodeGraphSceneBuilder.updateEdgeTransforms(root:)`를 호출해 연결된 엣지를 즉시 재계산
  - `onEnded`: 이동 거리가 3축 모두 2cm 미만이면 탭으로 판정해 노드 선택 토글

### T3. 전체 그래프 Magnify + Rotate (시선 무관, HIG 표준 두 손 제스처)

- [x] `MagnifyGesture()` / `RotateGesture3D(constrainedToAxis: nil)`를 각각 `.simultaneousGesture(_:)`로
      부착 (노드 드래그와 동시에 인식되도록). 둘 다 `.targetedToAnyEntity()`를 붙이지 않은 일반
      제스처이므로, 특정 엔티티를 응시/조준하지 않아도 시야 어디서든 인식된다
- [x] `committedScale`(누적 배율) × 현재 `magnification`을 루트 엔티티의 `scale`에 적용
- [x] `committedOrientation`(누적 회전) × 현재 회전값을 루트 엔티티의 `orientation`에 적용
  - `RotateGesture3D.Value.rotation`은 Spatial의 더블 정밀도 `Rotation3D`이므로,
    `.quaternion.vector`를 `SIMD4<Float>`로 낮춰 `simd_quatf(vector:)`로 변환한 뒤 곱한다
- [x] 두 제스처 모두 종료 시 각각의 커밋 상태에 결과를 반영

### T4. 엣지 실시간 재계산

- [x] `Rendering/CodeGraphSceneBuilder.updateEdgeTransforms(root:)` 신설
  - `EdgeEndpointsComponent`를 가진 모든 엣지/파티클 엔티티를 순회
  - 두 노드의 현재 위치로부터 실린더의 길이·중심·회전을 다시 계산해 갱신

---

## 설계 메모 / 트러블슈팅

- **탭과 드래그를 하나의 제스처로 처리**: `SpatialTapGesture`와 `DragGesture`를 각각 붙이면 두 제스처가
  서로 충돌(하나가 다른 하나를 막음)할 수 있어, `minimumDistance: 0`인 `DragGesture` 하나로 통합하고
  `onEnded`의 이동 거리로 탭/드래그를 사후 판별했다.
- **그래프 규모가 작다는 전제**: `updateEdgeTransforms`는 매 드래그 프레임마다 전체 엣지를 순회한다.
  PRD의 비기능 요구사항(노드 100개 이하에서 90fps)을 넘는 대규모 그래프에서는 드래그 중인 노드에
  연결된 엣지만 추적하는 인접 리스트 캐시가 필요할 것 — Phase 4 이후 실데이터 규모가 커지면 재검토.
- **Magnify/Rotate와 노드 드래그의 동시 인식**: 노드 드래그는 `.gesture(_:)`, Magnify·Rotate는
  각각 `.simultaneousGesture(_:)`로 붙여 서로의 인식을 막지 않도록 했다.

---

## 2차 개정 설계 메모

- **왜 커스텀 제스처를 버렸는가**: visionOS의 간접 제스처는 항상 "응시로 대상을 정한 뒤 핀치"다.
  대상이 보이지 않으면(투명 히트박스) 사용자는 어디를 봐야 하는지 알 수 없고, 뷰 전체에 붙인
  `MagnifyGesture`/`RotateGesture3D`는 서로 배타적으로 구분되지 않아 한 동작에 둘 다 반응했다.
  `ManipulationComponent`는 시스템이 한 손/두 손을 구분하고 이동·확대·회전을 한 번에 일관되게
  처리하므로, 앱이 제스처를 판별할 필요가 없다.
- **손잡이(HitTarget) 패턴**: 카드(SwiftUI)와 조작 영역(RealityKit)이 겹치면 입력이 경쟁한다.
  카드 아래에 별도 손잡이를 두고 `ManipulationComponent.HitTarget(redirectedEntity:)`로 노드에
  리다이렉트하면, 카드는 탭(SwiftUI), 손잡이는 이동(RealityKit)으로 역할이 분리된다. 이는 visionOS
  윈도우 본체/윈도우 바의 관계와 같다.
- **피벗**: 루트 엔티티가 그래프 중심(`layout.origin`)에 있으므로 두 손 확대/회전은 그래프 중심을
  기준으로 일어난다(1차 개정에서 고친 사항 유지).
- **미해결/추후**: 노드 손잡이에서도 두 손 조작이 가능해 개별 카드가 확대·회전될 수 있다.
  `ManipulationComponent.dynamics`로 회전/확대를 제한할 수 있는지 확인해 이동만 허용하도록 조이는 것을 후속 과제로 남긴다.

---

## 1차 개정 사항 (이력, 실기기 검증 후)

- **노드 도형 완전 제거**: "코드로 보여야 하는데 도형만 보인다"는 피드백을 받고, `NodeEntityFactory`에서
  `ModelComponent`(큐브/구체 메시·머티리얼)를 완전히 없앴다. 노드 엔티티는 이제 `CollisionComponent` +
  `InputTargetComponent`만 가진, 보이지 않는 히트박스다. 시각적 표현은 노드에 자식으로 붙는 코드 카드
  (Phase 2)뿐이다. 눈에 보이는 도형이 없어졌으므로 `HoverEffectComponent`도 함께 제거했다 — 하이라이트를
  그릴 표면 자체가 없기 때문이다.
- **Magnify/Rotate를 시선 무관 전역 제스처로 전환**: 처음부터 `MagnifyGesture()`는
  `.targetedToAnyEntity()`가 없어 원래도 시선과 무관했지만, 새로 추가한 `RotateGesture3D`도 동일하게
  타기팅 없이 붙여 두 제스처 모두 "어디를 보고 있든" 두 손 핀치만으로 반응한다. 이는 Apple HIG의 표준
  간접 제스처 정의("두 손으로 핀치 후 벌리거나 모으면 확대/축소", "두 손으로 핀치 후 원을 그리면 회전")를
  그대로 따른 것이다.
- **확대/회전 피벗을 그래프 중심으로 고정**: 기존에는 루트 엔티티가 세계 원점(사용자 발밑)에 있고
  자식 노드들이 눈높이 앞(`layout.origin`, y≈1.3m)에 절대 좌표로 배치되어 있었다. 이 상태에서 루트의
  `scale`을 키우면, 스케일이 원점을 기준으로 커지기 때문에 그래프 전체가 Y축을 따라 위로 솟아오르는
  것처럼 보였다. `Rendering/CodeGraphSceneBuilder.makeRootEntity`에서 **루트 자체를 `layout.origin`에
  위치시키고, 모든 자식을 그 기준 상대 좌표로 배치**하도록 고쳐, 확대·회전이 항상 그래프의 시각적
  중심을 피벗으로 삼게 했다.

---

## 다음 Phase로 넘기는 항목

- 실제 JSON 그래프 로드, 실행 흐름 파티클 애니메이션 → Phase 4
