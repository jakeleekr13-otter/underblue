# Hardware use: measurement and diagnosis (22 Oct 2026)

Question: do we use Apple hardware well? This page records what was measured. Nothing here is a fix.

## Setup

| Item | Value |
|---|---|
| Code | Rows 1–17: commit 7040d4f (before the export memory fix 9cee0d5). Rows 18–19: commit 9cee0d5. Frozen snapshots, Release `-O`, the app's own `Processing`, `Export`, `Models`, `Diagnostics` sources |
| Device | MacBook Air M3, 8 cores, 16 GB, on AC power |
| Clip A | 1080p H.264, 59.94 fps, 41.8 s (`tune/video/Tune_20_Oct/VID_20230118_095241_0018.MP4`) |
| Clip B | 720×1280 HEVC, 30 fps, 31.0 s (`tune/video/challenge_video/video3/Darwin’s Arch…MOV`) |
| Job | SDR export, source size, first 15 s (trace runs: first 8 s), preset Natural 0.8 |
| Tools | harness `hydrotone-eval-tools/perf` (outside git), `xctrace` 27.1 |

## Results

| # | Measurement | Result |
|---|---|---|
| 1 | Export speed, clip A, 3 runs | 24.8, 18.1, 18.4 fps (frame loop) |
| 2 | Export speed, clip B, 3 runs | 51.9, 40.5, 40.0 fps |
| 3 | Thermal state | 0 (nominal) on the first run, 1 (fair) after it. Speed fell about 27% with no code change. |
| 4 | Stage ceiling, clip A | decode only 888 fps; decode + render 25.6 fps; full export 24.8 fps |
| 5 | Stage ceiling, clip B | decode only 1958 fps; decode + render 46.8 fps; full export 51.9 fps |
| 6 | Time Profiler, export thread | 78% of samples inside `CIContext.render(toCVPixelBuffer)`. About 33% in `IOSurfaceClientSetPurgeable`. About 38% waiting in `mach_msg2_trap`. Copy next sample: 1%. Append to writer: 1%. |
| 7 | Metal System Trace, export loop | GPU compute busy about 35–40% (3 s bins: 33–46%, one bin 66%). About 10 300 compute intervals in the 40 s window. |
| 8 | Context option A/B, clip A, 4 alternating rounds | `cacheIntermediates: false` (app): 16.9, 14.7, 25.9, 23.5 fps. `true`: 11.5, 16.6, 17.1, 16.8 fps. |
| 9 | Core ML compute plan (`MLComputePlan`) | `.all`: 757 of 764 ops planned for the Neural Engine, 7 for GPU. `.cpuAndNeuralEngine`: 760 of 764 on the Neural Engine, 4 on CPU. |
| 10 | Analysis time, clip A / B | 2.99–6.49 s (first run includes model load) / 1.48–1.51 s |
| 11 | Resolution scaling, same graph, clip A, 3 rounds, best round (all rounds in brackets) | 1.00×: 25.4 fps (8.1, 24.9, 25.4). 0.50×: 86.1 (28.2, 86.1, 82.9). 0.25×: 176.2 (146.5, 49.6, 176.2). Identity (no filter): 1040 (672, 326, 1040). |
| 12 | Graph ablation, 1.00×, best round (all rounds) | Full: 25.4 fps = 39.4 ms. Current path only: 58.3 = 17.2 ms (33.4, 29.4, 58.3). No clarity and definition: 31.4 = 31.8 ms (17.3, 10.9, 31.4). No detail: 31.0 = 32.3 ms (11.2, 10.5, 31.0). No clarity, definition and detail: 37.3 = 26.8 ms (35.4, 16.7, 37.3). |
| 13 | Core Image tree, one frame, `CI_PRINT_TREE=7` | 350 nodes initial, 205 optimized, 119 in the program graph. 18 programs (passes) and 18 `CIBlurProcessor` nodes, sigma 1.6 to 162. Same counts at 1.00× and 0.50×. `intermediatesLimit=256MB`. |
| 14 | `memoryTarget` A/B, 1.00×, 4 rounds | default 256 MB: best 26.2 fps. 1024 MB: best 26.3. 64 MB: 2.4, 2.4, 2.4, 1.2 fps. |
| 15 | Concurrent renders (1, 2, 3 workers, 60 pre-decoded frames, 3 rounds) | 1 worker: best 25.9 fps (24.8, 25.9, 25.5). 2 workers: best 29.6 (28.7, 29.3, 29.6). 3 workers: best 28.6 (22.6, 28.6, 27.7). Checksum of the last frame is the same for all three. |
| 16 | Adaptive in-flight frames (probe window 30 frames, keep a step if gain is at least 5%, drop to 1 at thermal serious), idle machine, 3 interleaved rounds, 30 s gaps | fixed 1: 26.2, 26.0, 22.0 fps. Fixed 2: 26.2, 24.6, 21.1. Fixed 3: 26.7, 27.4, 27.3. Adaptive: 25.0, 25.8, 26.0 (final k = 2, 1, 1). Checksums of the captured frames were identical in every run (earlier single-policy runs also showed 1 distinct of 5). |
| 17 | Same policies while a second process renders on the GPU, 2 rounds | fixed 1: 14.0, 7.5 fps. Fixed 3: 12.8, 9.3. Adaptive: 7.2 (final k = 3), 9.7 (final k = 1). Heat drift between runs (14.0 to 7.5 for the same policy) is larger than any policy difference. |
| 18 | Export speed at 9cee0d5 (leak fixed, newer video algorithm), frame loop, 3 runs each | Clip A: 25.5, 25.7, 25.6 fps. Clip B: 54.0, 56.3, 51.5 fps. The spread is small. At 7040d4f the same clips gave 24.8, 18.1, 18.4 and 51.9, 40.5, 40.0 fps. |
| 19 | Time Profiler at 9cee0d5, export thread, 8 s of clip A | 89% of samples inside `CIContext.render`. 70% of the render time (3468 of 4955 samples) is `IOSurfaceClientSetPurgeable`, and every one of those samples ends in `mach_msg2_trap` (a blocking call). Decode and append: about 1% each. |
| 20 | `cacheIntermediates` A/B at 9cee0d5, clip A, 4 alternating rounds, thermal 0 | `false` (app): 24.6, 25.0, 25.1, 24.8 fps (mean 24.9). `true`: 26.2, 26.2, 25.5, 25.9 (mean 26.0). `true` was faster in every round (+4% on average). Memory use with `true` not measured. |
| 21 | Half-size blur variants, quality, 12 frames (clip A 2, 8, 20, 35 s; whale shark 2, 10, 20, 28 s; `instagram-media 2` 1, 3, 6, 8 s), 8-bit BGRA output of the real video path at 21f14c5, compared with the baseline build | Control, baseline against baseline: difference 0 in all frames (bit-identical). Variants v1 (two lift blurs), v2 (broad blur after the lift), v3 (soft calm blur), all three: worst frame mean difference 0.006 / 0.010 / 0.007 / 0.012 of 255, 99.9th percentile 1 level, maximum 3 levels, at most 0.002% of pixels above 2 levels. Worst frame (clip A, 35 s): 127 pixels at 2 or more levels. |
| 22 | Same variants, speed, frame loop, 3 rounds on clip A (8 s of clip) and 2 rounds on clip B (15 s), rotated order, 15 s gaps. Best round (all rounds) | Clip A: base 25.1 (25.1, 22.3, 7.5); v1 27.1 (27.1, 21.3, 17.0); v2 25.7 (25.7, 19.2, 24.4); v3 24.9 (24.9, 10.0, 24.5); all 28.1 (25.5, 21.8, 28.1). Clip B: base 55.0 (32.9, 55.0); v1 58.4 (58.4, 58.0); v2 56.0 (44.9, 56.0); v3 56.4 (53.1, 56.4); all 60.3 (60.3, 57.7). thermal state 1 in most rounds. |
| 23 | Visual check of the difference, worst frame, difference ×80 | Black with faint dot noise. One-level contour lines in the smooth bright surface area. No outline around the diver, no halo, no block pattern. |
| 24 | 4K baseline export at 9cee0d5, clip `13832750_2160_3840_60fps.MP4` (H.264, 2160×3840, 60 fps), first 5 s, 3 runs | 1.5, 1.7, 1.6 fps. Peak `phys_footprint` 4942, 4997, 5032 MB (Mac). Thermal 1. |
| 25 | `memoryLimit` (Swift `.memoryTarget`, MB) at 4K, render only, 130 frames, 2 rounds, 7 settings | Default: 1.9, 1.2 fps, 4655–5018 MB. 384: 1.8. 512: 2.7. 768: 5.1, 2084–2089 MB. 1024: 5.9, 5.7, 2256–2319 MB. 1536: 6.3, 3061–3124 MB. 2048: 6.3, 3310–3335 MB. |
| 26 | Output of row 25: checksum of the last frame | 768, 1024, 1536, 2048 MB: identical. Default, 384 and 512 MB: each different. |
| 27 | Default against 1024 MB, 6 frames of two 4K clips, 8-bit output | Mean difference 0.012–0.016 of 255, 99.9th percentile 1 level. A few isolated pixels differ up to 50 levels (clip 1: 221–251 pixels above 4 levels, 0.003%; clip 2: 7–20). No seam: at most 2 such pixels in any row or column. 768 against 1024 MB: difference 0. |
| 28 | Same setting at 1080p and 720×1280, render only, 2 rounds | 1080p: default 25.7 fps; 96 MB 6.1; 128 MB 10.2; 160 MB 11.7; 192 MB 14.7; 256 MB 23.2; 512 MB 24.8. 720×1280: default 51.0; 48 MB 11.6; 64 MB 20.7; 80 MB 28.3; 96 MB 29.8; 128 MB 36.6; 256 MB 51.1. |
| 29 | 4K full export (decode, render, encode), patched build (`FilterEngine(memoryLimitMB:)`, limit about 1 GB), first 5 s of the 4K clip, 3 runs | 5.2, 5.6, 5.2 fps. Peak `phys_footprint` 2369, 2324, 2367 MB. Thermal 1. Against row 24: about 3.3× the speed, about half the peak memory. |
| 30 | 8K full export, patched build, 1 s test clip (4320×7680 HEVC, 60 frames, made by enlarging the 4K clip, so no real 8K detail). The first version of the rule (125 bytes per pixel, cap at a sixth of the Mac's 16 GB) set the limit to about 2.7 GB. Rows 29 and 30 used that version. | 0.7 fps, peak 5228 MB. |
| 31 | 8K full export, default build, same clip (Mac) | Did not finish 60 frames in 86 minutes, then stopped by hand. Treat as unusable. |
| 32 | iPhone 17 (8 GB, Debug build, device-side XCTest, first 5 s of the 4K clip), baseline build (commit 6e895a5) | SDR: 2.40 fps, peak footprint 761 MB, minimum free memory 2615 MB, thermal 0 to 1. HLG: 1.84 fps, peak 595 MB, minimum free 2781 MB, thermal 2. |
| 33 | iPhone 17, patched build (limit about 1 GB), same clip | SDR: 5.05 fps (thermal 1) and 4.58 fps (thermal 2); peak 1236 and 1213 MB; minimum free 2141 and 2163 MB. HLG: 5.34 fps (thermal 2), peak 1192 MB, minimum free 2184 MB. The app was not ended. |
| 34 | iPhone 17, patched build, 8K source (1 s, 60 frames, enlarged from 4K) | Exported at 4K (2160×3840). SDR: 4.70 fps, peak 1308 MB. HLG: 4.58 fps, peak 1286 MB, `isHDR` true, output passed the exporter's own check. The HLG clips are SDR pictures with an HLG tag, so colour is not checked. |
| 35 | iPhone 17, 4K SDR, free memory lowered on purpose by holding memory in the test (policy limit = 80% of free memory) | About 2486 MB free: limit 1029, 5.71 fps, minimum free 1268 MB. About 987 MB free: limit 789, finished at 4.56 fps but minimum free fell to 11 MB, and the test process ended right after. |
| 36 | Same test, limit = free memory minus 512 MB | About 1493 MB free: limit 981, 5.28 fps, minimum free 392 MB. About 1236 MB free: limit 724, 2.37 fps, minimum free 363 MB. About 980 MB free: limit 468, the app was ended during the export (no result). |
| 37 | iPhone 17, 4K, same 6 frames rendered at each Core Image limit, 18 renders per limit (Debug build, device-side XCTest; free memory about 3.3 GB at the start). Pixels compared with the 2048 MB result | 2048 (reference) 6.95 fps. 1536: 7.51 fps, 0 differing bytes. 1024: 7.43, 0. 768: 6.79, 0. 640: 3.46, 5171 differing bytes, largest difference 2 levels. 512: 1.50, 5177, 2. 384: 0.75, 5188, 2. Default: 2.66, 5171, 2. |
| 38 | Mac, 1080p (2.07 MP) and 720×1280 (0.92 MP), render only, last frame checksum at each limit | 1080p: default, 192, 256, 384, 512, 1024 and 2048 MB all give the same checksum. 720×1280: default, 96, 128, 192, 256, 512 and 1024 MB give the same checksum; 64 MB differs. |
| 39 | iPhone 17, same 4K clip scaled to 1080×1920 and 720×1280, first frame compared with the 2048 MB result (Debug build) | 1080×1920: default, 192, 256, 384, 512 and 1024 MB identical (0 differing bytes). 128 MB: 15,981 bytes differ, largest difference 3. 96 MB: 17,817 bytes, 5. 64 MB: Core Image logged "memory requirement of 67683328 too big (tile 12x8)", part of the image was not rendered, 8.2 million bytes differ, largest difference 255. 720×1280: identical at every limit down to 64 MB and for the default (64 MB is half the speed, 24 fps against 49). |

## Diagnosis

| Earlier suspicion | Verdict | Evidence |
|---|---|---|
| Export loop is serial, so decode and encode idle the GPU | **Mostly refuted** | #4, #5, #6: decode and append are about 2% of the thread. Overlapping them would gain at most a few percent. |
| GPU is the limit | **Not shown** | #7: GPU is busy only about 35–40% while the export thread is blocked. |
| The render call is the limit | **Confirmed** | #4–#6: decode + render equals full export speed. |
| Core Image re-allocates intermediates each frame because `cacheIntermediates` is false | **Refuted as the main cause** | #8 (before the leak fix, noisy) showed no gain. #20 (after the fix, steady) shows `true` is +4%, faster in all 4 rounds. Small, and the memory cost is unknown. |
| Neural Engine is not used | **Refuted at plan level** | #9. Plan is not execution. Run time on the Neural Engine is `unmeasured`. |
| Analysis is a CPU bottleneck | **Not shown on Mac** | #10: 1.5–6.5 s. Sorting and `WaterModelEstimator` are small in the profile. |
| Cost is a fixed price per frame (surface allocation, sync) | **Mostly refuted** | #11: 39.4 ms at 1.00×, 11.6 ms at 0.50×, 5.7 ms at 0.25×. A line `a + b × pixels` through the first two points gives a = 2.3 ms, b = 37.1 ms. About 94% of the full-size frame time follows the pixel count. |
| Cost is in a few expensive filters | **Partly confirmed** | #12: clarity, definition and detail together cost about 12.6 ms (32%) of 39.4 ms. The restored path, its restore step and the blends cost about 22 ms (56%). The current path alone is 17 ms (44%). Both paths run the same finishing steps. |
| The export memory leak caused the purgeable-surface cost | **Refuted** | #19: after the fix the share rose (33% of the thread at 7040d4f, 62% at 9cee0d5). Speed on clip A is the same (about 25 fps). The leak did add heat and spread: #18 shows steadier runs. |
| The purgeable call blocks on the GPU | **Likely, not proven** | #19: the call is a blocking round trip. #11: its cost follows the pixel count, so it is not a fixed IPC cost. About 17 of 39 ms per frame sit in it. |
| Core Image spills intermediates because the 256 MB limit is too small | **Refuted** | #14: 1024 MB gives no gain. Forcing 64 MB makes it 10× slower, so reallocation is very costly, but the default does not hit it. |
| Overlapping frames raises speed | **Not reproduced** | #15 gave +14% for 2 workers. #16 gave 0 to +5% (fixed 3 best, 26.7–27.4 vs 26.2–26.0 fps). Output is identical in both. |
| Thermal limit | **Confirmed** | #3, #8: same code, 14.7 to 25.9 fps. A fanless Air cannot hold the first-run speed. |

Main finding: the export cost is in the Core Image render, and it grows with the pixel count and the number of passes. At full size one frame costs about 39 ms. About 17 ms is the current path. About 22 ms is the restored path and the blends. Clarity, definition and detail make up about 13 ms.

Open question: why does the GPU look only 35–40% busy (#7) while cost follows pixels and two overlapped frames give only +14%? The GPU is probably close to full in practice. The trace view may undercount. This is not resolved.

What this means for the goal (same quality, higher speed): the cost is the amount of full-size work. One frame runs 18 passes, 18 of them blurs, at full size in half-float. Overlapping frames is free of quality risk but gains little. Large gains need less full-size work.

Result of the memory limit test (rows 24–36): at 4K the default Core Image limit (256 MB) is too small. Raising it gives about 3× the speed on the Mac (1.9 to 5.9 fps) and about 2× on the iPhone 17 (2.4 to 4.6–5.1 fps). Output at 768 MB and above is bit-identical on the Mac. Against the default it differs in 0.003% of pixels, isolated, no seams. At 1080p and 720×1280 the default is already enough.

Rule in the app (updated after row 37):
- Smallest limit: 768 MB at 4K, scaled by pixel count. At 768 MB and above the frames are identical on the Mac (rows 26–27) and on the iPhone 17 (row 37). At 640 MB and below, about 0.016% of the bytes change by up to 2 levels, and the speed drops. The export never uses a limit below it.
- Limit: 130 bytes × pixels (1029 MiB at 4K, where the speed stops rising). The system default is kept when that is 300 MB or less (1080p and below). Checked at 1080p and 720×1280 (rows 38–39): the default gives the same pixels as a large limit on the Mac and on the iPhone 17. The smallest limit scaled by pixel count matches the measured knee at 1080p (192 MB). Too small a limit can break the picture (row 39, 64 MB at 1080p), which is one more reason the export never goes below the smallest limit.
- iPhone: also at most the free memory minus 512 MB, but not below the smallest limit. Free memory is `os_proc_available_memory()`. The first rule (80% of the free memory) left no room for the rest of the export (about 190 MB for decoder, encoder and buffers) and brought the iPhone to 11 MB free.
- Mac: the limit is fixed, not tied to the free memory. Nothing ends a Mac app for lack of memory, and a limit that followed the free memory would change pixels from one video of a batch to the next.
- Start check: at about 1 GB free the 4K export fails whatever the limit is. The app asks the user to close other apps when the free memory is below what the output needs (1300 MB for 4K; for a size with a limit set it is never below the smallest limit plus 512 MB; other sizes are estimates scaled by pixel count, only 4K was measured). It starts after the user taps "Check again" and the check passes.

Result of the half-size blur test (rows 21–23): computing the three video-only blurs at half size changes the output by 0.012 of 255 on average and by at most 3 levels. The best speed gain is about +10–12% for all three together (+6–8% for the lift blurs alone). The gain is a best-of-rounds figure; the Air throttled, and single rounds ranged from 7.5 to 28.1 fps. A patch is saved outside git (`hydrotone-eval-tools/perf/halfsize-blurs.patch`). It is not applied to the repo.

Status of rows 1–17: they were taken before the leak fix. Rows 15–17 (concurrent and adaptive runs) used harness code without a per-frame autorelease pool, so they may include the same leak. The video algorithm also changed after 7040d4f (one extra full-size colour pass and two extra blurs, per the other session: about 5–15% slower on the iPhone). The conclusions on pixel-proportional cost (#11) and on the render call (#6, #19) hold at both commits. The ablation shares (#12) are from 7040d4f only.

## Not measured

- iPhone: only the 4K clip (SDR, HLG-tagged SDR picture, 8K source brought down to 4K) at 5 s or 1 s. 1080p and 720p on the iPhone, 4K for the full clip length, 60 s or longer runs, and the old iPhones with less memory.
- Real HDR colour. The HLG test clips are SDR pictures with an HLG tag.
- The needed free memory for sizes other than 4K (scaled estimate). The identical-pixels check was run on one clip (4K scene, scaled) per size and on the first frame (iPhone) or the last frame (Mac) only.
- Mac pop-up flow on a real Mac under low memory (the check is built, the low-memory case was not run).
- Real Neural Engine run time and utilisation. Only the plan was read.
- Cost per Core Image pass (graph size, intermediate count) and per-frame allocation count.
- Power use, and speed after a long run on a cooled machine.
- Adaptive test under load (#17): heat drift hides the policy effect. A fair load test needs a cooled, fixed-clock machine or paired runs.
- Context A/B has 4 noisy rounds. A small effect would not show.
- Run-to-run spread is large (the same condition gave 8.1 and 25.4 fps). The tables use the best round as the unthrottled speed. Medians are lower.
- Node and intermediate counts per frame. The cost split in #12 is by feature, not by Core Image pass.

## Next steps (goal: same quality, faster, using Apple hardware)

Ranked by quality risk. Every step that changes pixels must pass the colour gate (memory: aquacolorfix-gate).

1. Overlapping frames: gain is 0 to 14% on this Mac and the output is identical. An adaptive controller works as designed (it probes, reverts, drops at high heat), but its 5% threshold is below the run-to-run noise (#16, #17), so its choices are close to random here. Use a larger threshold or paired probes before shipping, and measure on the iPhone first.
2. Compute smooth masks at a lower resolution. The blurs with sigma 54, 162 and 43 feed water-calm weights and scene masks. They are smooth, so a quarter-size render and an upscale should look the same. Measure the gain first, then the colour difference.
3. Check whether the current and restored paths can share their first steps (water-calm weight, outlier mask, subject weight appear in both).
4. Try clarity, definition and detail blurs at half size (about 13 ms of 39 ms).
5. Half-size blur patch (rows 21–23): about +10% on the Mac, output differs by 0.012 of 255 on average. Not applied. It belongs with the other session's colour gate.
6. Measure the iPhone at 1080p and for a full-length 4K clip, and lower the memory reserve test to other free-memory levels (900, 1100 MB).
7. Speed work on the colour algorithm waits until the algorithm is final (memory: algorithm-before-performance).
