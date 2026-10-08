# Core AI 실험 보존 데이터

[실험 기록](../../CoreAIExperiments.md)의 근거 자료다. 모델이나 원본 사진을 포함하지 않는 작은 결과 파일을 Git에 보관한다.

| 파일 | 내용 |
|---|---|
| [2026-10-05-gpu-input.json](2026-10-05-gpu-input.json) | CPU/GPU 입력 처리, Core ML 참고값, 반복 측정과 결과 일치 검사 |
| [2026-10-05-p6.json](2026-10-05-p6.json) | 최종 P6 압축 비교. 검증 오버헤드를 타이머에서 제외한 실행 |
| [2026-10-06-compute.json](2026-10-06-compute.json) | 자동/Neural Engine 선호/GPU 선호, 12회 측정과 깊이 비교 |
| [2026-10-06-ane-fallback.txt](2026-10-06-ane-fallback.txt) | FP32 중간값 오류와 GPU fallback을 확인하는 로그 발췌 |

JSON은 완료된 실험의 result.json을 그대로 복사했다. 로그 발췌에서는 기기 내부 경로와 프로세스 식별자를 제외했다. 첫 두 실험(2026-10-03)의 원시 임시 자료는 정리되어 대화 요약만 본문에 남겼다.

상세 시험 코드·모델 변환 코드·기기 로그·Xcode 결과·비교 이미지는 로컬의 다음 폴더에 있다. .build는 Git 제외 대상이므로 재생성하거나 삭제될 수 있다. 아래 경로는 보존된 JSON을 대체하는 근거가 아니라 추가 로컬 자료의 위치다.

~~~text
.build/experiments/coreai-gpu-input-20261005/
.build/experiments/coreai-p6-20261005/
.build/experiments/coreai-compute-20261006/
~~~

실험 모델: Depth Anything V2 Small, 원본 Hugging Face commit 5426e4f0f36572d16453bbda7a8389317b1bef99. Core AI 변환 도구 coreai-torch 0.4.3 / coreai-core 1.0.0b3, PyTorch 2.14.1, transformers 4.57.3. P6 직접 압축은 coreai-opt 0.3.0을 사용했다. 변환기가 검증한 PyTorch 범위 상한 2.13.0을 넘는 경고가 있었고 고정 입력 출력 비교를 별도로 수행했다.

재측정 시 기존 앱과 후보를 같은 실행에서 비교하고, 모델 파일·도구 버전·기기·OS·입력·색변환·준비 실행·측정 범위를 함께 기록한다. 서로 다른 날짜의 단일 중앙값 차이를 독립적인 개선 효과로 해석하지 않는다.
