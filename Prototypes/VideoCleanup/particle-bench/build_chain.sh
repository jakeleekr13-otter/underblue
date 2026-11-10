#!/bin/zsh
# Builds the D2 chain bench (chain.swift): the particle filter plus the app's colour sources.
# The binary, the kernels (default.metallib) and the depth model link go to $HT_PROTO_OUT/chainbin.
set -e
P=${0:A:h}; C=${P:h}; R=${C:h:h}; S=$R/UnderBlue/Processing
OUT=${HT_PROTO_OUT:-${TMPDIR:-/tmp}/underblue-video-cleanup/particles}/chainbin
mkdir -p $OUT
xcrun -sdk macosx metal -o $OUT/default.metallib $S/*.metal
# Renderer lives in measure_run.swift; take it alone so the other modes stay out.
sed -n '/^final class Renderer/,/^}/p' $P/measure_run.swift > $OUT/renderer.swift
sed -i '' '1i\
import CoreImage\
import VideoToolbox
' $OUT/renderer.swift
# Swift allows top-level code only in main.swift, so the entry point is written here.
cat > $OUT/main.swift <<'SWIFT'
import Foundation
let chainArgs = Array(CommandLine.arguments.dropFirst())
guard chainArgs.count >= 4, let s0 = Double(chainArgs[2]), let s1 = Double(chainArgs[3]) else {
    print("usage: chain <tag> <clip> <start> <seconds>"); exit(1)
}
try FileManager.default.createDirectory(atPath: root + "/chain", withIntermediateDirectories: true)
try await runChain(chainArgs[0], chainArgs[1], s0, s1)
SWIFT
# Every Processing file except the four app-only ones, the same set as videosim.
# A fixed list broke when the engines were split into extension files (6c9e2cb).
files=(); for f in $S/*.swift; do case ${f:t} in PhotoProcessor.swift|VideoPreview.swift|VideoColorPipeline.swift|PhotoHDR.swift) ;; *) files+=$f ;; esac; done
# stubs.swift replaces DiagnosticRecorder and the app error type. It lives outside git, next to the repo.
STUBS=${HT_STUBS:-$R/../hydrotone-eval-tools/videosim/stubs.swift}
[[ -f $STUBS ]] || { print -u2 "stubs not found: $STUBS (set HT_STUBS)"; exit 1 }
swiftc -O -swift-version 6 -o $OUT/chain $OUT/main.swift $P/chain.swift $OUT/renderer.swift $C/TemporalDenoiser.swift \
  $P/ParticleFilterV1.swift $P/common.swift $P/metric.swift $STUBS $files $R/UnderBlue/Models/VideoMetadata.swift
