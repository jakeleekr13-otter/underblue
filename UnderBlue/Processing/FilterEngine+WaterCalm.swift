import CoreImage
import CoreImage.CIFilterBuiltins

/// The water calm: where the water is (waterShare, waterCalmWeight) and the stages that act on it.
extension FilterEngine {
    /// The per-pixel water share, before the calm chain spreads it. Tier two of the lift reads its
    /// complement: a reef or a wreck is not open water, and Vision rarely returns one.
    func waterShare(_ basis: CIImage, correction v: ColorCorrection) -> CIImage? {
        guard let shareKernel = calmKernels["UnderBlueCalmShare"] else { return nil }
        let short = Float(min(basis.extent.width, basis.extent.height))
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = basis.clampedToExtent()
        blur.radius = max(0.5, FinishingMath.calmBlurRadius * (short.isFinite && short > 0 ? short : 480))
        let smooth = (blur.outputImage ?? basis).cropped(to: basis.extent)
        return shareKernel.apply(extent: basis.extent, arguments: [smooth,
            CIVector(x: CGFloat(v.castGains.x), y: CGFloat(v.castGains.y), z: CGFloat(v.castGains.z), w: 0),
            CIVector(x: CGFloat(v.waterRedness), y: CGFloat(v.waterChroma), z: 0, w: 0),
            CIVector(x: CGFloat(v.waterLit.x), y: CGFloat(v.waterLit.y), z: CGFloat(v.waterLit.z), w: CGFloat(v.lightGradient))])
    }

    /// The water calm weight (r) and water share (g) of `basis`, read with its values `v`. Nil when a
    /// kernel failed to load; the finishing then runs without the calm. See FinishingMath.calmShare.
    func waterCalmWeight(_ basis: CIImage, correction v: ColorCorrection) -> CIImage? {
        guard v != .identity, let shareKernel = calmKernels["UnderBlueCalmShare"],
              let spreadKernel = calmKernels["UnderBlueCalmSpread"], let weightKernel = calmKernels["UnderBlueCalmWeight"] else { return nil }
        let extent = basis.extent
        let side = Float(min(extent.width, extent.height))
        let short = side.isFinite && side > 0 ? side : 480
        func blurred(_ image: CIImage, _ radius: Float) -> CIImage {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image.clampedToExtent()
            blur.radius = max(0.5, radius * short)
            return (blur.outputImage ?? image).cropped(to: extent)
        }
        let smooth = blurred(basis, FinishingMath.calmBlurRadius)
        let gains = CIVector(x: CGFloat(v.castGains.x), y: CGFloat(v.castGains.y), z: CGFloat(v.castGains.z), w: 0)
        let water = CIVector(x: CGFloat(v.waterRedness), y: CGFloat(v.waterChroma), z: 0, w: 0)
        let waterLit = CIVector(x: CGFloat(v.waterLit.x), y: CGFloat(v.waterLit.y), z: CGFloat(v.waterLit.z), w: CGFloat(v.lightGradient))
        guard let share = shareKernel.apply(extent: extent, arguments: [smooth, gains, water, waterLit]),
              let spread = spreadKernel.apply(extent: extent, arguments: [smooth, blurred(share, FinishingMath.calmWindowRadius), share])
        else { return nil }
        return weightKernel.apply(extent: extent, arguments: [share, blurred(spread, FinishingMath.calmWindowRadius), basis, gains, water, waterLit,
            CIVector(x: CGFloat(FinishingMath.calmFlatLow), y: CGFloat(FinishingMath.calmFlatHigh), z: 0, w: 0)])
    }
    /// Open water moves toward a blur of water pixels only, before the colour stage. See waterCalmWeight.
    func waterCalm(_ image: CIImage, weight: CIImage?, short: Float) -> CIImage {
        guard let weight, let premultiply = calmKernels["UnderBlueCalmPremultiply"], let calm = calmKernels["UnderBlueWaterCalm"],
              let water = premultiply.apply(extent: image.extent, arguments: [image, weight]) else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = water.clampedToExtent()
        blur.radius = max(0.5, FinishingMath.calmBlurRadius * short)
        let waterBlur = (blur.outputImage ?? water).cropped(to: image.extent)
        return calm.apply(extent: image.extent, arguments: [image, waterBlur, weight]) ?? image
    }
    /// The weak part of the water's 3-12 px ripple comes off, before colour (UnderBlueWaterCore). The tone stage and the
    /// restored path amplified it into blotches (p3 1.69x, p2 2.16x). A wider calm blur fixed p3 but blurred away a faint
    /// distant hammerhead, so only the weak band goes. The weight's share (g) says where the water is.
    func waterCore(_ image: CIImage, weight: CIImage?, short: Float) -> CIImage {
        guard let weight, let kernel = calmKernels["UnderBlueWaterCore"] else { return image }
        func blurred(_ input: CIImage, _ radius: Float) -> CIImage {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = input.clampedToExtent()
            blur.radius = max(0.5, radius * short)
            return (blur.outputImage ?? input).cropped(to: image.extent)
        }
        let core = CIVector(x: CGFloat(FinishingMath.coreLow), y: CGFloat(FinishingMath.coreHigh), z: CGFloat(FinishingMath.coreStrength),
                            w: CGFloat(FinishingMath.coreOpenFrom))
        return kernel.apply(extent: image.extent, arguments: [image, blurred(image, FinishingMath.coreFineRadius),
                                                              blurred(image, FinishingMath.coreWideRadius), weight,
                                                              blurred(weight, FinishingMath.coreAroundRadius), core]) ?? image
    }

    /// Violet the correction made loses its chroma; a pixel that was violet in the source keeps it
    /// (FinishingMath.violetCalm). It runs once, on the colour that is shown. Per path it was wrong on
    /// m5: the restored path left the sand lavender and the source path cyan, and their blend was
    /// neutral (chroma 0.017); calming the restored lavender alone left the blend cyan (0.020).
    /// It only lowers chroma at the same lightness, so no channel crosses white.
    /// `calmWeight` (waterCalmWeight of the source) tells water from subjects; nil treats all as subject.
    func violetCalm(_ image: CIImage, source: CIImage, calmWeight: CIImage?) -> CIImage {
        guard let kernel = calmKernels["UnderBlueVioletCalm"] else { return image }
        let water = calmWeight ?? CIImage(color: .black).cropped(to: image.extent)
        return (kernel.apply(extent: image.extent, arguments: [image, source, water,
            CIVector(x: CGFloat(FinishingMath.violetCalmAmount), y: CGFloat(FinishingMath.violetWaterHue), z: 0, w: 0)]) ?? image).cropped(to: image.extent)
    }
}
