# PRD: Spatial IDE for visionOS (가칭: CodeSpace)

> 테크 PRD. Primitive의 공간 기반 코드 시각화 UX를 visionOS 네이티브 기술(SwiftUI + RealityKit)로 구현한다.
> 윈도우(Window)나 볼륨(Volume)의 경계 없이 `ImmersiveSpace` 안에서 코드를 3D 기하 구조로 펼친다.

---

## 1. 프로젝트 개요 (Product Overview)

| 항목 | 내용 |
| --- | --- |
| 목표 | 텍스트 기반 소스 코드를 3D 기하 모델로 변환·렌더링하고, 공간 안에서 코드를 읽고 조작할 수 있는 visionOS용 몰입형 개발 환경 |
| 공간 모드 | `ImmersiveSpace` (메인 씬, `WindowGroup` 대체) |
| 몰입 스타일 | `.progressive` 기본 — 디지털 크라운으로 패스스루가 걷히는 범위(몰입도)를 5%~100% 사이에서 조절. 걷힌 영역에는 어두운 스카이 돔 배경이 보임. `.mixed` / `.full` 전환도 가능 |
| 타깃 플랫폼 | visionOS 27.0+ (Apple Vision Pro) |

---

## 2. 핵심 기능 및 UI/UX 요구사항 (Core Features)

### A. 3D 공간 기하학 패러다임 (Spatial AST & Call Graph)

- **요구사항**: 코드 구조(모듈, 타입, 함수, 변수)를 3D 공간의 노드(구체, 큐브)로 렌더링하고, 호출 관계를 선(Edge)으로 연결하여 공간에 펼친다.
- **구현 전략**
  - RealityKit ECS: 노드마다 `ModelEntity`를 생성하고 `ModelComponent`로 형태와 머티리얼을 부여.
  - **Z축 레이아웃 알고리즘**: 호출 깊이(Call Depth)가 깊어질수록 시야에서 Z축 안쪽으로 노드를 배치. 같은 깊이의 노드는 X축으로 균등 분포, 노드 종류(kind)에 따라 Y축 오프셋.

### B. 2D 프로젝션 코드 창 (Floating UI)

- **요구사항**: 3D 노드 곁에 실제 소스 코드를 읽을 수 있는 2D 패널을 띄우고, 노드와 패널 간 시각적 동기화를 제공.
- **구현 전략**
  - `RealityView` attachments로 SwiftUI View를 특정 Entity 위치에 앵커링.
  - 노드를 응시하고 탭할 때만 애니메이션과 함께 패널을 표시하여 시각적 과부하 방지.

### C. 공간 인터랙션 및 네비게이션 (Spatial Interaction)

- **요구사항**: 그래프를 자유롭게 탐색하고, 노드를 잡아 이동시키거나 전체 그래프 크기를 조절.
- **구현 전략**
  - `.targetedToAnyEntity()` 기반 `DragGesture`, `MagnifyGesture`.
  - `HoverEffectComponent`로 응시(Hover) 시 미세 확대·발광 피드백.

### D. 동적 런타임 흐름 시각화 (Runtime Flow)

- **요구사항**: 데이터 이동이나 함수 실행 순서를 시각 이펙트로 표현.
- **구현 전략**
  - `ParticleEmitterComponent`로 엣지를 따라 흐르는 빛 궤적(Tracing) 애니메이션.

---

## 3. 기술 스택 및 데이터 파이프라인 (Tech Stack)

| 레이어 | 기술 |
| --- | --- |
| 앱 라이프사이클 / UI | SwiftUI (`ImmersiveSpace`를 메인 씬으로 사용) |
| 3D 렌더링 / 인터랙션 | RealityKit, `RealityView` |
| 상태 관리 | `@Observable` 모델 + SwiftUI Environment (Combine 미사용) |
| 코드 파싱 (옵션) | SwiftSyntax → AST → `CodeGraph` JSON |

### 데이터 모델 (초안)

```
CodeGraph
 ├─ nodes: [CodeNode]   // id, name, kind(module/type/function/variable), parentID
 └─ edges: [CodeEdge]   // from → to (호출/소유 관계)
```

- 호출 깊이(depth)는 저장하지 않고 엣지 그래프에서 BFS로 계산한다. (데이터와 레이아웃의 분리)

---

## 4. 단계별 개발 마일스톤 (Milestones)

| Phase | 목표 | 산출물 | 상태 |
| --- | --- | --- | --- |
| 1 | 공간 셋업 및 기본 렌더링 | `ImmersiveSpace` + `RealityView`, 더미 그래프 노드 배치 | 완료 → [태스크 문서](Tasks/Phase1_ImmersiveSpace_Skeleton.md) |
| 2 | 노드 연결 및 UI 어태치먼트 | 실린더 엣지 렌더링, 탭 시 SwiftUI 패널 팝업 | 완료 → [태스크 문서](Tasks/Phase2_NodeConnections_UIAttachment.md) |
| 3 | 인터랙션 적용 | Pinch-to-Drag, Hover 하이라이트, Magnify | 완료 → [태스크 문서](Tasks/Phase3_SpatialInteraction.md) |
| 4 | 실제 데이터 바인딩 및 파티클 | JSON AST 로드 → 자동 배치, 파티클 실행 흐름 | 완료 → [태스크 문서](Tasks/Phase4_DataBindingAndParticles.md) |
| 5 | Z축 코드 접힘(3축 코드 배열) | `catch`/`guard … else` 본문을 카드 뒤(-Z)로 꺾어 배치, 힌지 표식 | 1차 완료 → [태스크 문서](Tasks/Phase5_ZAxisCodeFolding.md) |

---

## 5. 비기능 요구사항 (Non-functional)

- 노드 100개 이하에서 90fps 유지 (Phase 1 기준 더미 데이터 ~15개).
- 시선/손 입력 외 별도 컨트롤러 요구 없음.
- 모든 3D 콘텐츠는 사용자 기준 1.0m ~ 3.0m 거리, 눈높이 근처(Y ≈ 1.0 ~ 1.6m)에 배치.
