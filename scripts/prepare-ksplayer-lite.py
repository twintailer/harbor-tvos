#!/usr/bin/env python3
"""Prepare a pinned, AVFoundation-only KSPlayer package for Harbor tvOS.

KSPlayer's full package links its own FFmpeg distribution. Harbor already ships
MPVKit, whose patched MoltenVK context is required for Anime4K on Apple TV. The
two FFmpeg graphs expose identical module names and cannot safely coexist.

This keeps KSPlayer's actual UI/player implementation and its KSAVPlayer engine,
while excluding only the optional KSMEPlayer/FFmpeg fallback.
"""

from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
TARGET = (ROOT / "Vendor" / "KSPlayerLite").resolve()
REVISION = "af2e26f68b5bf726463850fe19c23c08a0d56577"
MARKER = TARGET / ".harbor-revision"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def main() -> None:
    vendor_root = (ROOT / "Vendor").resolve()
    if TARGET.parent != vendor_root:
        raise RuntimeError(f"Refusing unexpected vendor target: {TARGET}")

    if MARKER.exists() and MARKER.read_text(encoding="utf-8").strip() == REVISION:
        print(f"KSPlayerLite already prepared at {REVISION}")
        return
    if TARGET.exists():
        raise RuntimeError(
            f"{TARGET} exists but is not the pinned Harbor package; remove that exact directory and retry"
        )

    vendor_root.mkdir(parents=True, exist_ok=True)
    run("git", "clone", "--filter=blob:none", "--no-checkout",
        "https://github.com/kingslay/KSPlayer", str(TARGET))
    run("git", "-C", str(TARGET), "checkout", "--detach", REVISION)

    me_player = TARGET / "Sources" / "KSPlayer" / "MEPlayer"
    if me_player.parent != TARGET / "Sources" / "KSPlayer":
        raise RuntimeError(f"Refusing unexpected MEPlayer path: {me_player}")
    shutil.rmtree(me_player)

    options = TARGET / "Sources" / "KSPlayer" / "AVPlayer" / "KSOptions.swift"
    source = options.read_text(encoding="utf-8")
    old = "static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self"
    new = "static var secondPlayerType: MediaPlayerProtocol.Type? = nil"
    if old not in source:
        raise RuntimeError("Pinned KSPlayer fallback declaration changed unexpectedly")
    source = source.replace(old, new, 1)
    renderer_check = "let isUseAudioRenderer = KSOptions.audioPlayerType == AudioRendererPlayer.self"
    if renderer_check not in source:
        raise RuntimeError("Pinned KSPlayer audio renderer check changed unexpectedly")
    source = source.replace(renderer_check, "let isUseAudioRenderer = false", 1)
    options.write_text(source, encoding="utf-8")

    recognize = TARGET / "Sources" / "KSPlayer" / "Subtitle" / "AudioRecognize.swift"
    recognize_source = recognize.read_text(encoding="utf-8")
    audio_frame_requirement = "public protocol AudioRecognize: SubtitleInfo {\n    func append(frame: AudioFrame)\n}"
    if audio_frame_requirement not in recognize_source:
        raise RuntimeError("Pinned KSPlayer audio recognition protocol changed unexpectedly")
    recognize.write_text(
        recognize_source.replace(audio_frame_requirement,
                                 "public protocol AudioRecognize: SubtitleInfo {}", 1),
        encoding="utf-8",
    )

    # A few color/deinterlace helpers live beside KSMEPlayer upstream even
    # though KSAVPlayer's shared protocols also reference them. Provide the
    # small platform-only subset without importing any FFmpeg module.
    support = '''import CoreGraphics
import CoreVideo

extension OSType {
    var bitDepth: Int32 {
        switch self {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
            return 10
        default:
            return 8
        }
    }
}

extension KSOptions {
    static var yadifMode = 0
    static var deInterlaceAddIdet = false

    static func colorSpace(ycbcrMatrix: CFString?,
                           transferFunction: CFString?) -> CGColorSpace? {
        switch ycbcrMatrix {
        case kCVImageBufferYCbCrMatrix_ITU_R_709_2:
            return CGColorSpace(name: CGColorSpace.itur_709)
        case kCVImageBufferYCbCrMatrix_ITU_R_2020:
            if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                if #available(tvOS 14.0, iOS 14.0, macOS 11.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
                }
                return CGColorSpace(name: CGColorSpace.itur_2020)
            }
            if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
                if #available(tvOS 14.0, iOS 14.0, macOS 11.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
                }
                return CGColorSpace(name: CGColorSpace.itur_2020)
            }
            return CGColorSpace(name: CGColorSpace.itur_2020)
        default:
            return CGColorSpace(name: CGColorSpace.sRGB)
        }
    }
}
'''
    (TARGET / "Sources" / "KSPlayer" / "AVPlayer" / "HarborLiteSupport.swift").write_text(
        support, encoding="utf-8"
    )

    manifest = '''// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KSPlayer",
    defaultLocalization: "en",
    platforms: [.macOS(.v10_15), .macCatalyst(.v14), .iOS(.v13),
                .tvOS(.v13), .visionOS(.v1)],
    products: [
        .library(name: "KSPlayer", targets: ["KSPlayer"]),
    ],
    targets: [
        .target(
            name: "KSPlayer",
            dependencies: ["DisplayCriteria"],
            exclude: [
                "Metal/DisplayModel.swift",
                "Metal/MetalRender.swift",
                "Metal/MotionSensor.swift",
                "Metal/PixelBufferProtocol.swift",
                "Metal/Transforms.swift",
            ],
            resources: [.process("Metal/Shaders.metal")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(name: "DisplayCriteria"),
    ]
)
'''
    (TARGET / "Package.swift").write_text(manifest, encoding="utf-8")
    MARKER.write_text(REVISION + "\n", encoding="utf-8")
    print(f"Prepared KSPlayerLite at {REVISION}")


if __name__ == "__main__":
    main()
