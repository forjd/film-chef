import CoreGraphics
import CoreImage
import Foundation

package struct FilmPipelineRenderer {
    package init() {}

    package func render(
        source: CIImage,
        recipe: FilmRecipe,
        adjustments: RenderAdjustments,
        calibration: CalibrationDataStatus = .descriptiveOnly
    ) -> CIImage {
        let extent = source.extent
        let intensity = clamped(adjustments.intensity, lower: 0.0, upper: 1.0)

        let normalised = normaliseInput(source, input: recipe.input)
        let exposed = applyExposure(
            to: normalised,
            exposure: recipe.exposure,
            adjustments: adjustments,
            intensity: intensity
        )
        let conditioned = applyCaptureConditions(
            to: exposed,
            conditions: recipe.captureConditions,
            stock: recipe.stock,
            intensity: intensity
        )
        let layerMapped = applyLayerModel(
            to: conditioned,
            layerModel: recipe.layerModel,
            stock: recipe.stock,
            intensity: intensity
        )
        let calibratedLayers = applyCalibrationChannelScales(
            to: layerMapped,
            calibration: calibration
        )
        let curved = applyCharacteristicCurves(
            to: calibratedLayers,
            curves: recipe.characteristicCurves,
            stock: recipe.stock,
            process: recipe.process,
            calibration: calibration,
            intensity: intensity
        )
        let colourRendered = applyColourResponse(
            to: curved,
            colourModel: recipe.colourModel,
            stock: recipe.stock,
            intensity: intensity
        )
        let processed = applyDevelopmentProcess(
            to: colourRendered,
            process: recipe.process,
            intensity: intensity
        )
        let withHalation = applyHalation(
            to: processed,
            reference: conditioned,
            halation: recipe.halation,
            extent: extent,
            intensity: intensity
        )
        let withGrain = applyGrain(
            to: withHalation,
            extent: extent,
            grain: recipe.grain,
            process: recipe.process,
            adjustments: adjustments,
            intensity: intensity
        )
        let withCalibratedGrain = applyCalibrationGrain(
            to: withGrain,
            extent: extent,
            calibration: calibration
        )
        let opticallyResolved = applySharpnessAndMTF(
            to: withCalibratedGrain,
            sharpness: recipe.sharpness,
            renderer: recipe.renderer,
            extent: extent,
            intensity: intensity
        )
        let rendered = applyScanOrPrintRenderer(
            to: opticallyResolved,
            renderer: recipe.renderer,
            colourModel: recipe.colourModel,
            stock: recipe.stock,
            adjustments: adjustments,
            intensity: intensity
        )

        return applyOutputTransform(
            to: rendered,
            output: recipe.output,
            extent: extent
        )
    }

    private func normaliseInput(_ image: CIImage, input: FilmInput) -> CIImage {
        guard input.requiresSceneLinear else {
            return image
        }

        // Core Image handles the actual bitmap color management. This stage is kept
        // explicit so profile rendering follows the same shape as calibrated engines.
        return image
    }

    private func applyExposure(
        to image: CIImage,
        exposure: FilmExposure,
        adjustments: RenderAdjustments,
        intensity: Double
    ) -> CIImage {
        var output = image
        let boxSpeed = max(Double(exposure.boxSpeedIso), 1.0)
        let exposedAt = max(Double(exposure.exposedAtIso), 1.0)
        let isoPlacementEv = log2(boxSpeed / exposedAt)
        let profileEv = exposure.exposureCompensationEv + isoPlacementEv
        let ev = (profileEv * intensity) + adjustments.exposureTrim

        if abs(ev) > 0.001 {
            output = output.applyingFilter(
                "CIExposureAdjust",
                parameters: ["inputEV": ev]
            )
        }

        let highlightProtection = exposure.highlightProtection ?? 0.0
        let shadowLift = exposure.shadowLiftBeforeFilm ?? 0.0

        if highlightProtection > 0.001 || shadowLift > 0.001 {
            output = output.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": clamped(1.0 - (highlightProtection * intensity), lower: 0.3, upper: 1.0),
                    "inputShadowAmount": shadowLift * intensity
                ]
            )
        }

        return output
    }

    private func applyCaptureConditions(
        to image: CIImage,
        conditions: FilmCaptureConditions,
        stock: FilmStock,
        intensity: Double
    ) -> CIImage {
        var output = image

        output = applyCaptureFilter(
            to: output,
            filter: conditions.filter,
            stock: stock,
            intensity: intensity
        )

        if stock.family != .blackAndWhiteNegative {
            // The capture filter's own temperature shift is applied in applyCaptureFilter;
            // this stage only balances native stock temperature against the capture light.
            let nativeTemperature = Double(stock.nativeColourTemperatureK ?? 5500)
            let captureTemperature = Double(conditions.colourTemperatureK)
            let targetTemperature = 6500.0 + ((nativeTemperature - captureTemperature) * 0.35) * intensity

            if abs(targetTemperature - 6500.0) > 1.0 {
                output = output.applyingFilter(
                    "CITemperatureAndTint",
                    parameters: [
                        "inputNeutral": CIVector(x: 6500, y: 0),
                        "inputTargetNeutral": CIVector(x: CGFloat(targetTemperature), y: 0)
                    ]
                )
            }
        }

        if let lensContrast = conditions.lensContrast, abs(lensContrast - 1.0) > 0.001 {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    "inputSaturation": 1.0,
                    "inputBrightness": 0.0,
                    "inputContrast": clamped(1.0 + ((lensContrast - 1.0) * intensity), lower: 0.5, upper: 1.8)
                ]
            )
        }

        if let lensFlare = conditions.lensFlare, lensFlare > 0.001 {
            let flare = lensFlare * intensity
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    "inputSaturation": 1.0,
                    "inputBrightness": flare * 0.04,
                    "inputContrast": clamped(1.0 - (flare * 0.35), lower: 0.65, upper: 1.0)
                ]
            )
        }

        return output
    }

    private func applyCaptureFilter(
        to image: CIImage,
        filter: FilmCaptureFilter,
        stock: FilmStock,
        intensity: Double
    ) -> CIImage {
        let strength = clamped(filter.strength * intensity, lower: 0.0, upper: 1.0)
        guard strength > 0.001 else {
            return image
        }

        let normalizedType = filter.type.lowercased()

        if stock.family == .blackAndWhiteNegative {
            let targetScales: FilmRGB
            switch normalizedType {
            case "yellow":
                targetScales = FilmRGB(r: 1.08, g: 1.04, b: 0.74)
            case "orange":
                targetScales = FilmRGB(r: 1.16, g: 1.00, b: 0.62)
            case "red":
                targetScales = FilmRGB(r: 1.28, g: 0.78, b: 0.48)
            case "green":
                targetScales = FilmRGB(r: 0.86, g: 1.18, b: 0.80)
            default:
                return image
            }

            return applyChannelScales(
                to: image,
                red: 1.0 + ((targetScales.r - 1.0) * strength),
                green: 1.0 + ((targetScales.g - 1.0) * strength),
                blue: 1.0 + ((targetScales.b - 1.0) * strength)
            )
        }

        switch normalizedType {
        case "85":
            return image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: CGFloat(6500.0 + (700.0 * strength)), y: 0)
                ]
            )
        case "80a":
            return image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: CGFloat(6500.0 - (900.0 * strength)), y: 0)
                ]
            )
        default:
            return image
        }
    }

    private func applyLayerModel(
        to image: CIImage,
        layerModel: FilmLayerModel,
        stock: FilmStock,
        intensity: Double
    ) -> CIImage {
        let identityRows = [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
        ]

        let rows: [[Double]]

        if stock.family == .blackAndWhiteNegative || layerModel.type.contains("monochrome") {
            let luminance = matrixRow(layerModel.rgbToLayerMatrix, index: 0, fallback: [0.30, 0.59, 0.11])
            rows = [
                mixedRow(from: identityRows[0], to: luminance, intensity: intensity),
                mixedRow(from: identityRows[1], to: luminance, intensity: intensity),
                mixedRow(from: identityRows[2], to: luminance, intensity: intensity)
            ]
        } else {
            rows = [
                mixedRow(from: identityRows[0], to: matrixRow(layerModel.rgbToLayerMatrix, index: 0, fallback: identityRows[0]), intensity: intensity),
                mixedRow(from: identityRows[1], to: matrixRow(layerModel.rgbToLayerMatrix, index: 1, fallback: identityRows[1]), intensity: intensity),
                mixedRow(from: identityRows[2], to: matrixRow(layerModel.rgbToLayerMatrix, index: 2, fallback: identityRows[2]), intensity: intensity)
            ]
        }

        return applyChannelMatrix(to: image, rows: rows)
    }

    private func applyCharacteristicCurves(
        to image: CIImage,
        curves: FilmCharacteristicCurves,
        stock: FilmStock,
        process: FilmProcess,
        calibration: CalibrationDataStatus,
        intensity: Double
    ) -> CIImage {
        guard intensity > 0.001,
              let averages = curveAverages(curves.channels)
        else {
            return image
        }

        var output = image
        let p1Y = clamped(0.12 + (averages.toe * 0.18), lower: 0.05, upper: 0.32)
        let p2Y = clamped(0.50 + ((averages.gamma - 1.0) * 0.18), lower: p1Y + 0.05, upper: 0.75)
        let p3Y = clamped(0.88 - (averages.shoulder * 0.18), lower: p2Y + 0.05, upper: 0.98)

        output = output.applyingFilter(
            "CIToneCurve",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 0.18, y: CGFloat(lerp(0.18, p1Y, intensity))),
                "inputPoint2": CIVector(x: 0.50, y: CGFloat(lerp(0.50, p2Y, intensity))),
                "inputPoint3": CIVector(x: 0.82, y: CGFloat(lerp(0.82, p3Y, intensity))),
                "inputPoint4": CIVector(x: 1, y: 1)
            ]
        )

        let baseContrast: Double
        switch stock.family {
        case .colourReversal:
            baseContrast = averages.gamma
        case .blackAndWhiteNegative:
            baseContrast = 1.0 + ((averages.gamma - 0.60) * 0.75)
        default:
            baseContrast = 1.0 + ((averages.gamma - 0.58) * 0.45)
        }

        let contrast = clamped(
            1.0 + (((baseContrast * process.contrastMultiplier) - 1.0) * intensity),
            lower: 0.55,
            upper: 1.8
        )

        output = output.applyingFilter(
            "CIColorControls",
            parameters: [
                "inputSaturation": 1.0,
                "inputBrightness": 0.0,
                "inputContrast": contrast
            ]
        )

        let densityRendered = applyDensityChannelResponse(to: output, curves: curves, intensity: intensity)
        return applyCalibrationDensityResponse(to: densityRendered, calibration: calibration)
    }

    private func applyColourResponse(
        to image: CIImage,
        colourModel: FilmColourModel,
        stock: FilmStock,
        intensity: Double
    ) -> CIImage {
        guard intensity > 0.001 else {
            return image
        }

        if stock.family == .blackAndWhiteNegative {
            guard let toning = colourModel.toning, toning.enabled else {
                return image
            }

            let warmth = clamped(toning.warmth, lower: -1.0, upper: 1.0)
            let selenium = clamped(toning.selenium, lower: 0.0, upper: 1.0)
            let colour = CIColor(
                red: CGFloat(0.95 + (warmth * 0.10) - (selenium * 0.06)),
                green: CGFloat(0.94 + (warmth * 0.05)),
                blue: CGFloat(0.90 - (warmth * 0.08) + (selenium * 0.12)),
                alpha: 1.0
            )

            return image.applyingFilter(
                "CIColorMonochrome",
                parameters: [
                    "inputColor": colour,
                    "inputIntensity": clamped((abs(warmth) + selenium) * 0.35 * intensity, lower: 0.0, upper: 0.45)
                ]
            )
        }

        var output = image

        if let warmth = colourModel.warmth, abs(warmth) > 0.001 {
            output = output.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: CGFloat(6500.0 + (warmth * 1200.0 * intensity)), y: 0)
                ]
            )
        }

        if let hueBias = colourModel.hueBias {
            let redScale = 1.0 + ((hueBias.reds + (hueBias.magentas * 0.35) + (hueBias.yellows * 0.20)) * 0.65 * intensity)
            let greenScale = 1.0 + ((hueBias.greens + (hueBias.yellows * 0.25) + (hueBias.cyans * 0.20)) * 0.65 * intensity)
            let blueScale = 1.0 + ((hueBias.blues + (hueBias.cyans * 0.30) + (hueBias.magentas * 0.25)) * 0.65 * intensity)

            output = applyChannelScales(
                to: output,
                red: clamped(redScale, lower: 0.75, upper: 1.25),
                green: clamped(greenScale, lower: 0.75, upper: 1.25),
                blue: clamped(blueScale, lower: 0.75, upper: 1.25)
            )
        }

        return output
    }

    private func applyDevelopmentProcess(
        to image: CIImage,
        process: FilmProcess,
        intensity: Double
    ) -> CIImage {
        guard intensity > 0.001 else {
            return image
        }

        var output = image
        let processEv = (process.speedGainEv + (process.pushPullStops * 0.12)) * intensity

        if abs(processEv) > 0.001 {
            output = output.applyingFilter(
                "CIExposureAdjust",
                parameters: ["inputEV": processEv]
            )
        }

        let contrast = clamped(
            1.0 + (((process.contrastMultiplier - 1.0) + (process.pushPullStops * 0.08)) * intensity),
            lower: 0.65,
            upper: 1.8
        )

        if abs(contrast - 1.0) > 0.001 {
            output = output.applyingFilter(
                "CIColorControls",
                parameters: [
                    "inputSaturation": 1.0,
                    "inputBrightness": 0.0,
                    "inputContrast": contrast
                ]
            )
        }

        if let colourShift = process.colourShift {
            output = applyChannelScales(
                to: output,
                red: clamped(1.0 + (colourShift.r * intensity), lower: 0.75, upper: 1.25),
                green: clamped(1.0 + (colourShift.g * intensity), lower: 0.75, upper: 1.25),
                blue: clamped(1.0 + (colourShift.b * intensity), lower: 0.75, upper: 1.25)
            )
        }

        return output
    }

    private func applyHalation(
        to image: CIImage,
        reference: CIImage,
        halation: FilmHalation,
        extent: CGRect,
        intensity: Double
    ) -> CIImage {
        guard halation.enabled,
              halation.strength > 0.001,
              halation.radius > 0.001,
              intensity > 0.001
        else {
            return image
        }

        let threshold = clamped(halation.threshold, lower: 0.0, upper: 0.99)
        let radius = max(0.25, halation.radius * (1.0 - ((halation.edgePreservation ?? 0.0) * 0.35)))
        let strength = clamped(halation.strength * intensity, lower: 0.0, upper: 1.0)

        // Map luminance in [threshold, 1] onto [0, 1] in one matrix: lum * rescale - threshold * rescale.
        // A contrast-based rescale is wrong here because CIColorControls pivots around 0.5.
        let rescale = 1.0 / max(0.04, 1.0 - threshold)
        let luminanceMask = reference
            .cropped(to: extent)
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: CGFloat(0.2126 * rescale), y: CGFloat(0.7152 * rescale), z: CGFloat(0.0722 * rescale), w: 0),
                    "inputGVector": CIVector(x: CGFloat(0.2126 * rescale), y: CGFloat(0.7152 * rescale), z: CGFloat(0.0722 * rescale), w: 0),
                    "inputBVector": CIVector(x: CGFloat(0.2126 * rescale), y: CGFloat(0.7152 * rescale), z: CGFloat(0.0722 * rescale), w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: CGFloat(-threshold * rescale), y: CGFloat(-threshold * rescale), z: CGFloat(-threshold * rescale), w: 0)
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                ]
            )
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: ["inputRadius": radius * intensity]
            )
            .cropped(to: extent)

        let glow = luminanceMask.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: CGFloat(halation.colour.r * strength), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(halation.colour.g * strength), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(halation.colour.b * strength), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(strength)),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]
        )

        return glow
            .applyingFilter(
                "CIScreenBlendMode",
                parameters: ["inputBackgroundImage": image]
            )
            .cropped(to: extent)
    }

    private func applyGrain(
        to image: CIImage,
        extent: CGRect,
        grain: FilmGrain,
        process: FilmProcess,
        adjustments: RenderAdjustments,
        intensity: Double
    ) -> CIImage {
        guard grain.enabled,
              adjustments.grainEnabled,
              grain.strength > 0.001,
              intensity > 0.001,
              let random = CIFilter(name: "CIRandomGenerator")?.outputImage
        else {
            return image
        }

        let distributionMultiplier: Double
        if let tonalDistribution = grain.tonalDistribution {
            distributionMultiplier = (tonalDistribution.shadow + tonalDistribution.midtone + tonalDistribution.highlight) / 3.0
        } else {
            distributionMultiplier = 1.0
        }

        let size = clamped(grain.size, lower: 0.35, upper: 3.0)
        let clumpiness = clamped(grain.clumpiness, lower: 0.0, upper: 1.0)
        let alpha = clamped(
            grain.strength * process.grainMultiplier * distributionMultiplier * (1.0 + (clumpiness * 0.35)) * intensity,
            lower: 0.0,
            upper: 0.58
        )

        var noise = random
            .transformed(by: CGAffineTransform(scaleX: size, y: size))
            .cropped(to: extent)

        let softnessRadius = grain.softness * size * 1.6
        if softnessRadius > 0.01 {
            noise = noise
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: ["inputRadius": softnessRadius]
                )
                .cropped(to: extent)
        }

        let chromaticity = clamped(grain.chromaticity, lower: 0.0, upper: 1.0)
        let variance = grain.channelVariance ?? FilmChannelValues(red: 1.0, green: 1.0, blue: 1.0)
        let monoWeight = (1.0 - chromaticity) / 3.0

        let shapedNoise = noise.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(
                    x: CGFloat(monoWeight + (chromaticity * variance.red)),
                    y: CGFloat(monoWeight),
                    z: CGFloat(monoWeight),
                    w: 0
                ),
                "inputGVector": CIVector(
                    x: CGFloat(monoWeight),
                    y: CGFloat(monoWeight + (chromaticity * variance.green)),
                    z: CGFloat(monoWeight),
                    w: 0
                ),
                "inputBVector": CIVector(
                    x: CGFloat(monoWeight),
                    y: CGFloat(monoWeight),
                    z: CGFloat(monoWeight + (chromaticity * variance.blue)),
                    w: 0
                ),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))
            ]
        )

        return shapedNoise
            .applyingFilter(
                "CISoftLightBlendMode",
                parameters: ["inputBackgroundImage": image]
            )
            .cropped(to: extent)
    }

    private func applyCalibrationChannelScales(
        to image: CIImage,
        calibration: CalibrationDataStatus
    ) -> CIImage {
        guard calibration.supportsThreeDimensionalLUTs || calibration.supportsSpectralCurves else {
            return image
        }

        let redScale = clamped(calibration.redScale, lower: 0.5, upper: 1.5)
        let greenScale = clamped(calibration.greenScale, lower: 0.5, upper: 1.5)
        let blueScale = clamped(calibration.blueScale, lower: 0.5, upper: 1.5)

        guard abs(redScale - 1.0) > 0.001 ||
              abs(greenScale - 1.0) > 0.001 ||
              abs(blueScale - 1.0) > 0.001
        else {
            return image
        }

        return image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: CGFloat(redScale), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(greenScale), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(blueScale), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]
        )
    }

    private func applyCalibrationDensityResponse(
        to image: CIImage,
        calibration: CalibrationDataStatus
    ) -> CIImage {
        let densityGamma = clamped(calibration.densityGamma, lower: 0.75, upper: 1.35)
        guard calibration.supportsMeasuredDensityCurves,
              abs(densityGamma - 1.0) > 0.001
        else {
            return image
        }

        return image.applyingFilter(
            "CIGammaAdjust",
            parameters: ["inputPower": densityGamma]
        )
    }

    private func applyCalibrationGrain(
        to image: CIImage,
        extent: CGRect,
        calibration: CalibrationDataStatus
    ) -> CIImage {
        let grainAmount = clamped(calibration.grainAmount, lower: 0, upper: 0.25)
        guard calibration.supportsGrainSpectra,
              grainAmount > 0.001,
              let random = CIFilter(name: "CIRandomGenerator")?.outputImage
        else {
            return image
        }

        let noise = random
            .cropped(to: extent)
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    "inputSaturation": 0.0,
                    "inputBrightness": 0.0,
                    "inputContrast": 1.0 + (grainAmount * 10.0)
                ]
            )
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: CGFloat(grainAmount), y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: CGFloat(grainAmount), z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(grainAmount), w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 0.5 - CGFloat(grainAmount / 2), y: 0.5 - CGFloat(grainAmount / 2), z: 0.5 - CGFloat(grainAmount / 2), w: 0)
                ]
            )

        return noise
            .applyingFilter(
                "CISoftLightBlendMode",
                parameters: ["inputBackgroundImage": image]
            )
            .cropped(to: extent)
    }

    private func applySharpnessAndMTF(
        to image: CIImage,
        sharpness: FilmSharpness,
        renderer: FilmRenderer,
        extent: CGRect,
        intensity: Double
    ) -> CIImage {
        guard intensity > 0.001 else {
            return image
        }

        var output = image
        let scannerBlur = renderer.scannerMtf?.blurRadius ?? 0.0
        let blurRadius = (sharpness.filmMtfBlur + sharpness.scannerMtfBlur + scannerBlur) * intensity

        if blurRadius > 0.01 {
            output = output
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: ["inputRadius": blurRadius]
                )
                .cropped(to: extent)
        }

        let microcontrast = renderer.scannerMtf?.microcontrast ?? 0.0
        let sharpening = sharpness.acutance + sharpness.digitalSharpening + (renderer.sharpening ?? 0.0) + microcontrast
        let unsharpIntensity = clamped(sharpening * intensity, lower: 0.0, upper: 1.2)

        if unsharpIntensity > 0.001 {
            output = output.applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    "inputRadius": clamped(1.0 + blurRadius, lower: 0.5, upper: 4.0),
                    "inputIntensity": unsharpIntensity
                ]
            )
        }

        return output.cropped(to: extent)
    }

    private func applyScanOrPrintRenderer(
        to image: CIImage,
        renderer: FilmRenderer,
        colourModel: FilmColourModel,
        stock: FilmStock,
        adjustments: RenderAdjustments,
        intensity: Double
    ) -> CIImage {
        var output = image

        if renderer.negativeInversion, stock.hasOrangeMask, let orangeMask = colourModel.orangeMask, orangeMask.enabled {
            output = applyOrangeMaskCompensation(to: output, orangeMask: orangeMask, intensity: intensity)
        }

        let autoExposureEv = (renderer.autoExposure - 0.5) * 0.18 * intensity
        if abs(autoExposureEv) > 0.001 {
            output = output.applyingFilter(
                "CIExposureAdjust",
                parameters: ["inputEV": autoExposureEv]
            )
        }

        if stock.family != .blackAndWhiteNegative, renderer.autoWhiteBalance > 0.001 {
            let warmth = (colourModel.warmth ?? 0.0) * renderer.autoWhiteBalance * 450.0 * intensity
            if abs(warmth) > 1.0 {
                output = output.applyingFilter(
                    "CITemperatureAndTint",
                    parameters: [
                        "inputNeutral": CIVector(x: 6500, y: 0),
                        "inputTargetNeutral": CIVector(x: CGFloat(6500.0 + warmth), y: 0)
                    ]
                )
            }
        }

        let blackPoint = renderer.blackPoint * intensity
        let whitePoint = 1.0 - ((1.0 - renderer.whitePoint) * intensity)
        output = applyBlackWhitePoints(to: output, blackPoint: blackPoint, whitePoint: whitePoint)

        let baseSaturation = renderer.saturation * (colourModel.saturation ?? 1.0)
        let saturation = clamped(
            1.0 + ((baseSaturation - 1.0) * intensity) + adjustments.saturationTrim,
            lower: 0.0,
            upper: 2.5
        )
        let contrast = clamped(
            1.0 + ((renderer.contrast - 1.0) * intensity) + adjustments.contrastTrim,
            lower: 0.25,
            upper: 2.5
        )

        output = output.applyingFilter(
            "CIColorControls",
            parameters: [
                "inputSaturation": saturation,
                "inputBrightness": 0.0,
                "inputContrast": contrast
            ]
        )

        return output
    }

    private func applyOutputTransform(to image: CIImage, output: FilmOutput, extent: CGRect) -> CIImage {
        var rendered = image

        if output.dither {
            rendered = rendered.applyingFilter(
                "CIDither",
                parameters: ["inputIntensity": 0.1]
            )
        }

        return rendered.cropped(to: extent)
    }

    private func applyOrangeMaskCompensation(
        to image: CIImage,
        orangeMask: FilmOrangeMask,
        intensity: Double
    ) -> CIImage {
        let density = orangeMask.density
        let averageDensity = (density.red + density.green + density.blue) / 3.0
        let redScale = 1.0 - ((density.red - averageDensity) * 0.22 * intensity)
        let greenScale = 1.0 - ((density.green - averageDensity) * 0.22 * intensity)
        let blueScale = 1.0 - ((density.blue - averageDensity) * 0.22 * intensity)

        return applyChannelScales(
            to: image,
            red: clamped(redScale, lower: 0.85, upper: 1.15),
            green: clamped(greenScale, lower: 0.85, upper: 1.15),
            blue: clamped(blueScale, lower: 0.85, upper: 1.15)
        )
    }

    private func applyDensityChannelResponse(
        to image: CIImage,
        curves: FilmCharacteristicCurves,
        intensity: Double
    ) -> CIImage {
        guard let red = curves.channels["red"],
              let green = curves.channels["green"],
              let blue = curves.channels["blue"]
        else {
            return image
        }

        let redRange = red.dMax - red.dMin
        let greenRange = green.dMax - green.dMin
        let blueRange = blue.dMax - blue.dMin
        let averageRange = (redRange + greenRange + blueRange) / 3.0

        let redScale = 1.0 + ((redRange - averageRange) * 0.06 * intensity)
        let greenScale = 1.0 + ((greenRange - averageRange) * 0.06 * intensity)
        let blueScale = 1.0 + ((blueRange - averageRange) * 0.06 * intensity)

        return applyChannelScales(
            to: image,
            red: clamped(redScale, lower: 0.9, upper: 1.1),
            green: clamped(greenScale, lower: 0.9, upper: 1.1),
            blue: clamped(blueScale, lower: 0.9, upper: 1.1)
        )
    }

    private func applyBlackWhitePoints(
        to image: CIImage,
        blackPoint: Double,
        whitePoint: Double
    ) -> CIImage {
        let black = clamped(blackPoint, lower: 0.0, upper: 0.95)
        let white = clamped(whitePoint, lower: black + 0.01, upper: 1.0)
        let scale = 1.0 / (white - black)
        let bias = -black * scale

        return applyChannelMatrix(
            to: image,
            rows: [
                [scale, 0.0, 0.0],
                [0.0, scale, 0.0],
                [0.0, 0.0, scale]
            ],
            bias: FilmRGB(r: bias, g: bias, b: bias)
        )
    }

    private func applyChannelScales(
        to image: CIImage,
        red: Double,
        green: Double,
        blue: Double
    ) -> CIImage {
        applyChannelMatrix(
            to: image,
            rows: [
                [red, 0.0, 0.0],
                [0.0, green, 0.0],
                [0.0, 0.0, blue]
            ]
        )
    }

    private func applyChannelMatrix(
        to image: CIImage,
        rows: [[Double]],
        bias: FilmRGB = FilmRGB(r: 0.0, g: 0.0, b: 0.0)
    ) -> CIImage {
        let red = matrixRow(rows, index: 0, fallback: [1.0, 0.0, 0.0])
        let green = matrixRow(rows, index: 1, fallback: [0.0, 1.0, 0.0])
        let blue = matrixRow(rows, index: 2, fallback: [0.0, 0.0, 1.0])

        return image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: CGFloat(red[0]), y: CGFloat(red[1]), z: CGFloat(red[2]), w: 0),
                "inputGVector": CIVector(x: CGFloat(green[0]), y: CGFloat(green[1]), z: CGFloat(green[2]), w: 0),
                "inputBVector": CIVector(x: CGFloat(blue[0]), y: CGFloat(blue[1]), z: CGFloat(blue[2]), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat(bias.r), y: CGFloat(bias.g), z: CGFloat(bias.b), w: 0)
            ]
        )
    }

    private func matrixRow(_ matrix: [[Double]], index: Int, fallback: [Double]) -> [Double] {
        guard matrix.indices.contains(index), matrix[index].count >= 3 else {
            return fallback
        }

        return Array(matrix[index].prefix(3))
    }

    private func mixedRow(from identity: [Double], to target: [Double], intensity: Double) -> [Double] {
        zip(identity, target).map { start, end in
            lerp(start, end, intensity)
        }
    }

    private func curveAverages(
        _ channels: [String: FilmCharacteristicCurve]
    ) -> (toe: Double, gamma: Double, shoulder: Double, dMin: Double, dMax: Double)? {
        guard !channels.isEmpty else {
            return nil
        }

        let curves = Array(channels.values)
        let count = Double(curves.count)

        return (
            curves.reduce(0.0) { $0 + $1.toe } / count,
            curves.reduce(0.0) { $0 + $1.gamma } / count,
            curves.reduce(0.0) { $0 + $1.shoulder } / count,
            curves.reduce(0.0) { $0 + $1.dMin } / count,
            curves.reduce(0.0) { $0 + $1.dMax } / count
        )
    }

    private func lerp(_ start: Double, _ end: Double, _ amount: Double) -> Double {
        start + ((end - start) * amount)
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
