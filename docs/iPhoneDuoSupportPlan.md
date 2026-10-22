# iPhone Duo 대응 계획

작성일: 2026-10-07  
상태: 1단계 구현 (2026-10-07), 2단계는 Xcode 27.1 대기  
참조 문서:
- [Apple HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Apple Developer: Preparing your app for iPhone Duo](https://developer.apple.com/kr/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)

---

## 1. 개요 및 배경

Apple의 첫 폴더블 스마트폰인 **iPhone Duo**(2026년 9월 공개, 10월 출시)는 5.4인치 외측 커버 디스플레이와 7.6인치 내측 메인 폴더블 디스플레이로 구성됩니다.
iOS 27.1 및 Xcode 27.1부터 폴더블 폼팩터 전용 레이아웃 컨테이너와 힌지/가림 감지 API가 도입되었으며, **2027년 4월부터 App Store 심사 시 iPhone Duo 규격 스크린샷 제출이 의무화**됩니다.

UnderBlue는 수중 사진 및 동영상 전용 보정 앱으로, 대화면과 반접힘(Tabletop) 모드에서 프리뷰와 제어판의 공간 효율을 극대화할 수 있는 잠재력이 매우 높습니다. 본 문서는 공식 가이드라인을 준수하며 UnderBlue를 iPhone Duo 폼팩터에 완벽히 대응하기 위한 아키텍처 및 구현 로드맵을 정의합니다.

---

## 2. 공식 가이드라인 및 핵심 기술 요약

### 2.1 하드웨어 및 폼팩터 특성
* **외측 커버 디스플레이 (Folded)**: 5.4인치, Compact Width (`compact`). 한 손 조작 중심의 컴팩트 뷰.
* **내측 메인 디스플레이 (Unfolded/Flat)**: 7.6인치 나노 텍스처 디스플레이, Regular Width (`regular`). 1:1에 가까운 대화면.
* **반접힘 포즈 (Partially Folded / Tabletop / Book)**: 힌지(Fold crease)를 기준으로 두 면으로 나뉘며 기기를 세우거나 눕혀 거치할 수 있는 상태.
* **하드웨어 가림 영역**:
  * `division`: 반접힘 시 힌지/주름 부분.
  * `occlusion`: 내측 전면 카메라 컷아웃 영역.

### 2.2 소프트웨어 원칙 (HIG)
1. **화면 연속성 (Continuity)**:
   * 기기를 열거나 닫을 때 Scene이나 ViewController를 재시작하지 않고, 현재 보고 있던 미디어 확대/스크롤/재생 상태 및 작업 중인 조정값을 실시간으로 유지해야 함.
2. **반응형 적응 (Adaptive Layouts over Detection)**:
   * 화면 크기나 기기 식별자를 하드코딩하지 않고, `horizontalSizeClass`, `verticalSizeClass`, Safe Area Insets에 맞춰 유연하게 리사이징.
   * 단순히 화면을 늘리는(stretching) 것이 아니라 넓어진 공간을 가치 있게 활용(Earn the extra space).
3. **힌지 및 가림 영역 회피 (Reserved Regions)**:
   * 힌지 주름선 위에 텍스트, 버튼, 슬라이더, 썸네일 경계선이 걸치지 않도록 여백을 두거나 상하/좌우로 인터랙션 분리.

### 2.3 iOS 27.1 신규 개발자 API
* **`ArrangementView` (SwiftUI) / `UIArrangementViewController` (UIKit)**:
  * Primary(예: 프리뷰)와 Secondary(예: 컨트롤 패널) 뷰를 기기 접힘 포즈와 가로/세로 비율에 맞춰 `.split` 및 `.overlay` 형태로 자동 재배치.
* **`ReservedRegion` (`GeometryProxy.reservedRegions(kind:options:)`)**:
  * `.division` (힌지 접힘선) 및 `.occlusion` (카메라 가림 영역)의 CGRect를 반환받아 하위 뷰 배치에 반영.
* **`toolbarVerticalEdge` / `verticalBarEdge`**:
  * 대화면 또는 접힘 상태에서 상/하단 바를 화면 측면(사이드)으로 배치해 수직 공간 확보.
* **포즈/힌지 관찰**:
  * SwiftUI `.onHingeChange`, UIKit `UIHingeInteraction`을 통한 각도 전환 애니메이션 및 전환 시점 처리.

---

## 3. UnderBlue 영향 분석 및 변경 사항

| 화면 / 컴포넌트 | 현재 구현 방식 | iPhone Duo 환경에서의 문제점 | 대응 계획 |
|---|---|---|---|
| **[EditorView.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/EditorView.swift)** | `geometry.size.width > geometry.size.height` 단순 비교로 HStack/VStack 분기. 컨트롤 너비 `min(330, width * 0.42)`, 높이 `min(350, height * 0.48)` 고정 | 7.6인치 정사각 비율에서 세로 모드로 오판정되거나, Tabletop 반접힘 시 힌지 선에 프리뷰/슬라이더가 걸침 | 1. `horizontalSizeClass == .regular` 대응.<br>2. iOS 27.1+ 환경에서 `ArrangementView` 도입 또는 `.division` 힌지 기준 상하 분할(상단: 프리뷰, 하단: 슬라이더/프리셋).<br>3. 줌/팬 상태(`PreviewZoom`) 연속성 보존. |
| **[ZoomablePreview.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/ZoomablePreview.swift)** | 단일 뷰포트 기준 핀치/더블탭 줌 | 펼치거나 접는 전환(Transition) 시 스케일 튐 현상 방지 필요 | 화면 크기 변경 시에도 확대 중심점과 상대 배율 유지 확인 |
| **[HomeView.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/HomeView.swift)** | 단일 세로 스택(VStack)으로 모든 버튼 수직 정렬 | 7.6인치 펼침 화면에서 양옆 여백 과다 및 버튼이 지나치게 길어짐 | Regular 환경에서 2열 배치(좌측: 타이틀/Hero 브랜딩, 우측: 가져오기 및 동작 버튼)로 최적화 |
| **[BatchView.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/BatchView.swift)** | 그리드 열(Column) 구성 | 커버(5.4")에서는 2열이 적절하나 내측(7.6")에서는 3~4열이 적절함 | 동적 GridItem(적응형 그리드) 적용으로 열 개수 자동 조절 |
| **타깃 버전 호환성** | iOS 26+ 타깃 | iOS 27.1 전용 API를 직접 호출하면 iOS 26에서 런타임 오류 | `@available(iOS 27.1, *)` 가드 적용 및 폴백(GeometryReader 기반 분할) 병행 |

---

## 4. 상세 레이아웃 설계

### 4.1 EditorView 포즈별 동작 정의

```
[포즈 A: 커버 디스플레이 (5.4" Folded - Compact)]
┌────────────────┐
│  미디어 프리뷰   │  (상단 55~60%)
│  (사진/동영상)   │
├────────────────┤
│  프리셋/슬라이더 │  (하단 40~45% 스크롤)
└────────────────┘

[포즈 B: 펼침 디스플레이 (7.6" Unfolded/Flat - Regular)]
┌───────────────────┬──────────────┐
│                   │ 원본/비교    │
│    미디어 프리뷰   ├──────────────┤
│    (대화면 표시)   │ 프리셋 목록   │
│                   ├──────────────┤
│                   │ 세부 슬라이더 │
└───────────────────┴──────────────┘
  (좌측: 넓은 프리뷰)    (우측: 사이드 제어판)

[포즈 C: 반접힘 Tabletop 포즈 (Partially Folded - Hinge active)]
┌────────────────────────────────┐
│        상단 화면: 미디어 프리뷰   │  <- 시야각 확보 (거치 모드)
╞════════════════════════════════╡  <- Hinge (ReservedRegion .division)
│  하단 화면: 조작 패널 (터치)    │  <- 프리셋 선택, 비교 토글, 슬라이더
└────────────────────────────────┘
```

1. **Tabletop 모드 (거치형 편집)**:
   * 다이빙 후 테이블 위에 기기를 L자형(반접힘)으로 세워두고, 상단 화면으로는 수중 사진/영상을 감상하며 하단 화면에서는 조작부만 편안하게 터치할 수 있는 독보적인 UX 제공.
   * 동영상 재생 시(3s Preview / 전체 재생) 상단 화면이 클린 뷰어로 전환.

### 4.2 화면 전환 연속성 보장
* `scenePhase` 변경 시 취소 로직(백그라운드 진입 시 내보내기 취소 등)은 유지하되, 디스플레이 접힘/펼침은 단순 **TraitCollection / SizeClass 변경**으로 취급.
* 모델 인스턴스(`EditorModel`)가 재생성되지 않고 SwiftUI 뷰의 내부 상태(`@State private var zoom`, `@Bindable var model`)가 그대로 유지되는지 검증.

---

## 5. 단계별 실행 계획 및 완료 조건

### 1단계: 기본 적응형 레이아웃 구축 (iOS 26 호환)
* **작업**:
  * `horizontalSizeClass` 환경 변수 도입.
  * [EditorView.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/EditorView.swift)의 가로/세로 분기 기준을 단순 `width > height`에서 `sizeClass` 및 종횡비 복합 조건으로 개선.
  * [HomeView.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/HomeView.swift)의 Regular 너비 2열 레이아웃 지원.
  * [BatchView.swift](file:///Users/jakelee/personal_project/hydrotone/UnderBlue/Views/BatchView.swift) 썸네일 그리드 열 개수 유동화.
* **완료 조건**:
  * iPad 시뮬레이터 및 기존 iPhone 가로 모드에서 레이아웃 깨짐 없이 올바르게 사이드바 형태로 분할됨.
  * 기존 iOS 26 단위/UI 테스트 전체 통과.

### 2단계: iOS 27.1 iPhone Duo 특화 API 연동
* **작업**:
  * `@available(iOS 27.1, *)`를 통한 힌지 감지 로직 추가.
  * `GeometryProxy.reservedRegions(kind: .division)`를 활용한 Tabletop 분기 컨테이너 구현.
  * 접힘선 주변 안전 패딩(`safeAreaInset`) 보정으로 제어부가 주름선과 겹치지 않도록 보호.
* **완료 조건**:
  * Xcode 27.1 시뮬레이터에서 반접힘 상태 시뮬레이션 시 프리뷰(상단)와 제어판(하단)이 힌지를 경계로 완벽히 분리됨.

### 3단계: 품질 보증 및 회귀 테스트 (QA)
* **작업**:
  * [QA.md](file:///Users/jakelee/personal_project/hydrotone/docs/QA.md)에 iPhone Duo 테스트 매트릭스 항목 추가.
  * 접힘 ↔ 펼침 실시간 전환 시 메모리 누수(`DiagnosticRecorder`), 렌더링 파이프라인 중단 여부 점검.
  * 비교(Compare) 모드 토글 및 줌 배율 유지 확인.
* **완료 조건**:
  * 실시간 접힘 전환 중 크래시 0건, 메모리 경고 없이 즉각적인 리레이아웃 확인.

### 4단계: App Store 에셋 및 심사 준비
* **작업**:
  * iPhone Duo 7.6인치 내부 디스플레이 스크린샷 템플릿 확보 (2027년 4월 의무 제출 기준 준수).
  * [AppStoreMetadata.md](file:///Users/jakelee/personal_project/hydrotone/docs/AppStoreMetadata.md) 및 [AppStoreRelease.md](file:///Users/jakelee/personal_project/hydrotone/docs/AppStoreRelease.md)에 듀오 스크린샷 규격 반영.
* **완료 조건**:
  * 스크린샷 생성 스크립트 규격 확인 완료.

---

## Progress (7 Oct 2026)

Stage 1 is in the code. Stage 2 waits for Xcode 27.1.

| Item | Status | Check |
|---|---|---|
| `EditorView` side panel | Done. Landscape, or a regular-width screen with width ≥ 0.85 × height (`EditorView.squareAspect`) | Unit test `testEditorUsesSidePanelInLandscapeAndOnWideNearSquareScreens`. The near-square case is unmeasured on a screen: no simulator has that shape |
| Zoom across fold/unfold | Done. `PreviewZoom.resized` keeps the scale and the centre point, then clamps the pan to the new frame. Before, the offset was not re-clamped, so a gap could open | Unit test `testResizeKeepsScaleAndCentrePointInsideTheNewFrame` |
| `HomeView` two columns | Done for regular width | Screenshot: iPad Air 11" simulator (build with `TARGETED_DEVICE_FAMILY=1,2` on the command line only). iPhone 17 portrait is unchanged |
| `BatchView` grid | No change needed. It already uses `GridItem(.adaptive(minimum: 104))`, so the column count follows the width | Code read |
| Stage 2 APIs | Unblocked (19 Oct 2026). Xcode 27.1 (27A9275, SDK 27.1) has `GeometryProxy.reservedRegions(kind:options:)`, `ArrangementView`, `toolbarVerticalEdge`, `UIHingeInteraction` and `UIArrangementViewController`. `onHingeChange` is not in the SwiftUI interface | `grep` of the iPhoneOS27.1 SDK |
| Fold split (all screens) | Done (19 Oct 2026). An active `.division` region splits the screen: content on the first pane, controls on the second, a spacer over the fold. Screens: `EditorView`, `BatchView`, `BatchDetailView`, `HomeView`. Presets become a two-column grid in the narrow pane. A pane under 160 pt is ignored. Older iOS keeps the old layout. `ArrangementView` is not used. Shared code: `FoldSplit`, `FoldPanes` in `EditorView.swift` | Unit tests `FoldSplitTests` (4) and `PreviewZoomTests` (5) pass on the iPhone Duo simulator. Screenshots of each screen on the half-folded inner display: the division was x 455.5–495.5 pt (log). No content crossed it |
| Cover display | Unchanged. It has no division region, so the old layout runs. Its safe area already keeps clear of the system bar (trailing 84 pt) | Log of the cover display |
| Portrait half-fold (top and bottom panes) | `EditorView` checked on screen: preview above the fold, controls below, nothing on the fold. A wide pane keeps the sideways preset row, so Export stays in view. A narrow pane (side by side) uses the two-column grid. `HomeView` in this posture uses the single column and clears the fold by its spacing, not by fold code | Screenshots of the inner display (19 Oct 2026). `BatchView` (grid) and `BatchDetailView` checked in this posture too: thumbnails or photo above the fold, controls below, fold clear |
| Video preview on the Duo simulator | Fails on both displays: black preview, "cannot play" icon, Stop button stuck. Cause found with a test outside the app (19 Oct 2026): on the iOS 27.1 Duo simulator, any Core Image video composition fails, even one that changes nothing (`AVPlayerItem.status` = failed, error -11800 / OSStatus -12784). A plain `AVPlayer` plays the same file there. The same composition works on the iOS 26.5 simulator (iPhone 17) and the iOS 27.0 simulator (iPhone 18 Pro). The Duo is the only iOS 27.1 simulator, so runtime and device cannot be told apart. A real iPhone 17 plays the video through the app. A real Duo is not tested. App gap seen on screen: when the item fails to load, the UI shows no error and stays on Stop | Test runs on three simulators, screenshots of both Duo displays, player log |
| Export sheet (photo) in a fold | Landscape fold: iOS puts the sheet on the left pane. Content ends before the fold (x 952 px of the 958–1042 px fold band); the sheet edge reaches about 12 pt into the fold band. Portrait fold: the sheet covers the whole display (`presentationDetents([.large])`). The section title "Format" sits on the fold band. The Format picker starts about 24 pt below the band. A video sheet has more rows (Resolution list, Color): not seen, so a control may land on the fold | Screenshots of the inner display (19 Oct 2026) |
| Not checked | Rotation while folded. Video editor layout in a fold (the preview does not play, so only the controls are seen). Export sheets in a fold. Unit tests were last run before the grid-only-when-narrow change; the build after it succeeded | Unmeasured |

Open: the app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). Whether the Duo inner display reports regular width is not verified.

## 6. 결론 및 다음 단계

UnderBlue의 iPhone Duo 대응은 단순한 호환성 확보를 넘어, **대화면 컬러 그레이딩 및 거치형(Tabletop) 편집**이라는 강력한 사용자 가치를 제공할 수 있는 기회입니다.

계획 승인 시 **1단계(EditorView 및 HomeView 기본 적응형 레이아웃 리팩토링)**부터 즉시 코드 변경을 진행합니다.
