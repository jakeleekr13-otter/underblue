# Core AI 연동 실험 기록

기록일: 2026-10-06
상태: 깊이 추정 교체 실험 완료. 앱의 기존 Core ML + Core Image/Metal 경로 유지.

## 결론

현재 시험한 Core AI 깊이 추정 경로는 최적화 후에도 기존 Core ML보다 느렸다. 마지막 같은 조건 비교에서 깊이 분석 전체 시간은 Core ML 32.96ms, Core AI GPU 선호 40.81ms였다. 이 결과는 **이 모델·이 기기·이 구현에 대한 판단**이며 Core AI 전체가 느리다는 결론은 아니다.

보정 화질 개선도 입증하지 못했다. 앱의 Swift/Metal 처리 코드는 실험 때문에 변경하지 않았다. 모든 모델 변환과 기기 시험은 별도 복사본에서 수행했다.

기존 보정 결과에 노이즈 제거·디테일 복원을 추가하는 작업은 다른 목적의 실험으로 분리했다. 이후 작은 Core AI refiner까지 만들고 사용자 비교를 했지만 체감 이득이 없어 [개발을 보류했다](AIRefinerPilot.md).

## 현재 구조와 시험 범위

- 사진은 이미 Depth Anything V2 Small Core ML 깊이 추정과 Metal 복원을 사용한다. Vision 피사체 마스크도 일부 사용한다.
- 기존 렌더링은 Core Image + Metal이다. AI를 처음 도입하는 실험이 아니라 **깊이 추정 실행 경로를 바꾸는 실험**이었다.
- 기존 Core ML 모델은 Apple 배포 FP16/P6 모델이다. Core AI 후보는 같은 V2 Small 계열의 공개 가중치를 변환했다. 동일 바이너리나 동일 세부 압축 레시피는 아니다.
- Core AI 모델 입력은 518×392, 상대 깊이 출력이다. 실제 수심(m)을 측정하지 않는다.
- Core AI는 iOS 27 이상 경로다. 앱은 iOS 26도 지원하므로 제품화한다면 기존 Core ML 경로가 필요하다. [Apple Core AI 모델 통합](https://developer.apple.com/documentation/coreai/integrating-on-device-ai-models-in-your-app-with-core-ai)

관련 코드: [DepthEstimator](../UnderBlue/Processing/DepthEstimator.swift), [PhotoProcessor](../UnderBlue/Processing/PhotoProcessor.swift), [RestorationEngine](../UnderBlue/Processing/RestorationEngine.swift).

## 공통 측정 조건과 해석

- 실제 iPhone 17, iOS 27.0.1 (24A446), Release 최적화, 디버거 미사용.
- 속도 입력: m6 수중 만타 사진 1600×900. 모델 입력은 518×392로 축소한다.
- 준비 실행 2회씩 제외. 아래 시간은 중앙값이다.
- 추론 시간: 모델 실행만 포함한다.
- 깊이 분석 전체: 입력 렌더링/변환, 추론, 깊이 복사와 정규화를 포함한다. 최초 로드, 최종 색 보정 렌더링, 저장·영상 내보내기는 제외한다.
- 표가 다른 실험의 수치를 하나의 연속 측정처럼 합치거나, 깊이 분석 시간을 앱 전체 FPS로 환산하지 않는다.
- 마지막 세 실험의 시작/종료 발열 상태는 nominal이고 저전력 모드는 꺼져 있었다. 장시간 발열·배터리·GPU 동시 부하·전체 앱 메모리는 측정하지 않았다.
- 원시 출력과의 차이는 화질 정확도 점수가 아니다. 정답 깊이/색상에 대한 평가를 한 것이 아니다.

## 1. 기존 Core ML 실행 장치 비교 — 2026-10-03

같은 기존 모델의 자동 선택과 CPU + Neural Engine 설정을 각 10회 교대 측정했다.

| 설정 | 추론 | 깊이 분석 전체 |
|---|---:|---:|
| 자동 선택 | 20.11ms | 32.27ms |
| CPU + Neural Engine | 20.22ms | 33.11ms |

비교한 깊이 지도는 동일했다. 실행 장치를 제한할 속도 이득은 확인하지 못했다.

이 표는 당시 대화에 보고한 결과를 옮긴 **초기 요약 기록**이다. 당시 임시 폴더가 정리되어 원시 로그는 현재 보존되어 있지 않다.

## 2. Core AI FP16 첫 연결 — 2026-10-03

FP16 비압축 V2 Small을 Core AI로 변환해 각 10회 비교했다.

| 경로 | 추론 | 깊이 분석 전체 |
|---|---:|---:|
| 기존 Core ML | 20.63ms | 33.05ms |
| Core AI FP16 시제품 | 44.50ms | 73.42ms |

실제 모델 실행과 기존 보정 파이프라인 연결에 성공했다. 다만 후보는 비압축 가중치와 CPU 텐서 변환을 사용해 조건이 달랐다. m6/m5/O3 출력에 차이가 있었고 화질 향상은 입증하지 못했다.

이 표도 초기 대화 요약이며 원시 임시 자료는 유실됐다. 이후 실험에서 같은 모델을 다시 준비해 측정했다.

## 3. GPU 입력 변환 + 버퍼 재사용 — 2026-10-05

동일 Core AI 모델과 같은 추론 함수를 유지했다. 각 방식 12회, 세 방식의 모든 순서를 두 번씩 사용했다.

| 경로 | 입력 준비 | 추론 | 깊이 분석 전체 |
|---|---:|---:|---:|
| 기존 Core ML 참고값 | 별도 측정 안 함 | 20.62ms | 32.78ms |
| Core AI CPU 입력 변환 | 20.32ms | 43.93ms | 72.55ms |
| Core AI GPU 입력 변환 | 2.64ms | 44.03ms | 55.65ms |

입력 준비는 약 87%, 깊이 분석 전체는 약 23% 줄었다. 효과는 GPU 변환과 버퍼 재사용의 합이다.

비대칭 합성 입력과 사진 3장의 입력 텐서는 비트 단위로 일치했다. 사진 3장의 원시/정규화 깊이도 동일했다. 처음 사용한 직접 RGBA 텍스처 렌더링은 실제 사진의 일부 RGB 값이 1/255 달라져 폐기했고, 기존과 같은 ARGB 렌더링으로 수정했다.

CPU의 픽셀별 변환은 제거했지만 공유 staging 버퍼로 일괄 복사 한 번이 남는다. **완전한 zero-copy 구현은 아니다.** 재사용 버퍼는 순차 시험용이며, 제품의 중첩 요청에는 별도 실행 제한이나 버퍼 풀이 필요하다.

[보존한 원시 측정값](experiments/coreai/2026-10-05-gpu-input.json)

## 4. 6비트 가중치 압축 — 2026-10-05

FP16 Core AI 모델 그래프에 직접 P6 압축을 적용했다. GPU 입력 처리는 유지했다. 각 방식 12회 측정했다.

| 경로 | 추론 | 깊이 분석 전체 | 원본 모델 파일 |
|---|---:|---:|---:|
| 기존 Core ML 참고값 | 20.54ms | 33.23ms | 19.04MB |
| Core AI FP16 + GPU 입력 | 43.46ms | 53.91ms | 49.52MB |
| Core AI P6 + GPU 입력 | 29.73ms | 42.38ms | 19.49MB |

Core AI 내부 비교에서 추론 약 32%, 깊이 분석 전체 약 21%, 모델 파일 약 61%가 줄었다. 파일 용량은 설치 앱 전체 크기나 실행 메모리 사용량이 아니다.

최종 압축은 Apple의 기존 Core AI 모델 직접 압축 API를 사용했다. 설정은 per-tensor 6비트 scalar palette, FP16 LUT, 원소 64개 이하의 작은 텐서 제외, fast rounding 꺼짐이다. 저장된 IR에서 LUT 복원 연산 102개와 ui6 인덱스를 확인했다. 앞선 PyTorch 압축→변환 경로는 비트 수 불일치로 실패해 사용하지 않았다. [Apple 압축 안내](https://apple.github.io/coreai-optimization/utils/coreai_compression.html)

같은 Natural 0.8 보정과 공통 색 분석/피사체 마스크를 사용했다. 압축 전 Core AI와의 비교:

| 사진 | 정규화 깊이 평균 차이(0~1) | RGB 평균 차이 | RGB 최대 차이 |
|---|---:|---:|---:|
| m6 만타 | 0.01615 | 1.21/255 | 20/255 |
| m5 산호/색상표 | 0.00468 | 0.44/255 | 189/255 |
| O3 개복치 | 0.00561 | 0.85/255 | 33/255 |

평균 차이가 작아도 일부 픽셀은 크게 달라진다. 무손실 또는 화질 개선으로 판정하지 않는다. 검사 코드가 타이머에 포함된 첫 실행은 제외하고, 타이머를 결과 반환 직후 종료한 최종 실행을 기록했다.

[보존한 최종 측정값](experiments/coreai/2026-10-05-p6.json)

## 5. Core AI 실행 장치 선호 비교 — 2026-10-06

동일 P6 모델·입력·후처리를 유지하고 로드 옵션만 바꿨다. 각 12회, 네 방식의 위치와 직전 실행 영향을 균형화했다.

| 경로 | 추론 | 깊이 분석 전체 |
|---|---:|---:|
| 기존 Core ML 참고값 | 20.51ms | 32.96ms |
| Core AI 자동 선택 | 29.45ms | 41.79ms |
| Neural Engine 선호 → GPU fallback | 29.53ms | 41.76ms |
| GPU 선호 | 27.87ms | 40.81ms |

GPU 선호의 전체 중앙값 차이는 약 1ms이며 실행 시간 범위가 겹친다. 일반적인 속도 우위로 단정하지 않는다. 사진 3장의 원시/정규화 깊이와 confidence는 세 설정에서 동일했다.

Neural Engine 선호 설정에서는 다음 로그가 기록됐다.

> ANE cannot handle intermediate tensor type fp32

이어서 ANE 선호 컴파일 실패 후 GPU 전체 컴파일로 전환한다는 로그가 나왔다. 따라서 위 행은 **Neural Engine 정상 실행 성능이 아니다.** 이 모델의 어떤 노드가 FP32를 남기는지까지 특정하지 않았다. 모든 Neural Engine 모델의 제한으로 일반화하지 않는다.

선호 설정은 전용 실행을 보장하지 않는다. 자동/GPU 선호의 연산별 실제 배치는 Instruments로 추적하지 않았다. [Apple 설정](https://developer.apple.com/documentation/coreai/specializationoptions/preferredcomputeunitkind), [특수화·캐시](https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching)

[보존한 측정값](experiments/coreai/2026-10-06-compute.json), [핵심 fallback 로그](experiments/coreai/2026-10-06-ane-fallback.txt)

## 보존 자료와 한계

[실험 데이터 안내](experiments/coreai/README.md)에 Git에 보관하는 자료와 로컬 산출물을 구분했다. 이 문서와 JSON/핵심 로그는 임시 폴더 없이도 읽을 수 있다.

- 10월 5~6일의 세 실험은 각각 XCTest 1개 통과, 실패 0개다. 시스템의 GPU fallback이 있었으므로 테스트 통과를 ANE 성공으로 해석하지 않는다.
- 기기에서 MDB_MAP_FULL 캐시 진단이 반복됐다. 최초 로드 속도는 비교 결론에 사용하지 않았다.
- PyTorch 기준 출력과 FP16 Core AI의 고정 입력 RMSE는 출력 범위 대비 0.248%였다. 이는 변환 계산 확인이며 수중 깊이 정확도 인증이 아니다.
- P6·Core ML의 세부 압축/변환 조건이 다르므로 프레임워크 단독 비교가 아니다.
- 비교 모델의 동영상·HDR·48MP 사진 전체 처리 성능이나 학습 정답 기준 화질은 검증하지 않았다.
- FP32 중간값을 정리한 ANE용 FP16 모델은 **미시험**이다.
- 작은 AI 노이즈 제거 후처리는 별도 파일럿에서 시험했으며 체감 이득이 없어 보류했다. 확대와 다른 복원 구조는 미시험이다.

현재 결정은 깊이 추정 경로와 기존 보정 결과를 유지하는 것이다. [사진 후처리 검토](CoreAIPostProcessing.md)는 보류된 설계 기록으로 남긴다.
