import Foundation

package struct CalibrationAssetParser {
    private enum CalibrationAssetKind {
        case spectral
        case density
        case grain
    }

    private struct JSONCalibrationAsset {
        var values: [Double]
        var kinds: Set<CalibrationAssetKind>
        var lutScale: (red: Double, green: Double, blue: Double)?
    }

    package enum CalibrationImportError: LocalizedError {
        case unsupportedAsset(String)
        case invalidAsset(String, String)

        package var errorDescription: String? {
            switch self {
            case .unsupportedAsset(let name):
                return "\(name) is not a supported calibration asset."
            case .invalidAsset(let name, let reason):
                return "\(name) is not a valid calibration asset. \(reason)"
            }
        }
    }

    package init() {}

    package func parse(urls: [URL]) throws -> CalibrationDataStatus {
        var lutScale = (red: 1.0, green: 1.0, blue: 1.0)
        var supportsLUT = false
        var supportsSpectral = false
        var supportsDensity = false
        var supportsGrain = false
        var spectralValues: [Double] = []
        var densityValues: [Double] = []
        var grainValues: [Double] = []
        var assetSummaries: [String] = []

        for url in urls {
            let name = url.lastPathComponent.lowercased()
            switch url.pathExtension.lowercased() {
            case "cube":
                lutScale = try parseCubeCalibration(url)
                supportsLUT = true
                assetSummaries.append(assetSummary(name: url.lastPathComponent, labels: ["3D LUT"]))
            case "json":
                let asset = try parseJSONCalibration(url)
                var labels = asset.kinds.map(kindLabel)
                if let typedLUTScale = asset.lutScale {
                    lutScale = typedLUTScale
                    supportsLUT = true
                    labels.append("RGB scale")
                }
                if asset.kinds.isEmpty {
                    append(asset.values, named: name, spectral: &supportsSpectral, density: &supportsDensity, grain: &supportsGrain, spectralValues: &spectralValues, densityValues: &densityValues, grainValues: &grainValues)
                    labels.append(contentsOf: labelsForName(name))
                } else {
                    append(asset.values, kinds: asset.kinds, spectral: &supportsSpectral, density: &supportsDensity, grain: &supportsGrain, spectralValues: &spectralValues, densityValues: &densityValues, grainValues: &grainValues)
                }
                assetSummaries.append(assetSummary(name: url.lastPathComponent, labels: labels))
            case "csv", "txt":
                let values = try parseDelimitedCalibration(url)
                append(values, named: name, spectral: &supportsSpectral, density: &supportsDensity, grain: &supportsGrain, spectralValues: &spectralValues, densityValues: &densityValues, grainValues: &grainValues)
                assetSummaries.append(assetSummary(name: url.lastPathComponent, labels: labelsForName(name)))
            default:
                throw CalibrationImportError.unsupportedAsset(url.lastPathComponent)
            }
        }

        let spectralSignal = calibrationSignal(spectralValues)
        let densitySignal = calibrationSignal(densityValues)
        let grainSignal = calibrationSignal(grainValues)
        let spectralBias = supportsSpectral ? 0.025 + (spectralSignal * 0.02) : 0
        let names = urls.map(\.lastPathComponent).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        return CalibrationDataStatus(
            supportsSpectralCurves: supportsSpectral,
            supportsMeasuredDensityCurves: supportsDensity,
            supportsGrainSpectra: supportsGrain,
            supportsThreeDimensionalLUTs: supportsLUT,
            importedAssetNames: names,
            importedAssetSummaries: assetSummaries.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            },
            redScale: lutScale.red * (1.0 + spectralBias),
            greenScale: lutScale.green,
            blueScale: lutScale.blue * (1.0 - spectralBias),
            densityGamma: supportsDensity ? 1.0 + (densitySignal * 0.08) : 1.0,
            grainAmount: supportsGrain ? 0.035 + (grainSignal * 0.045) : 0.0,
            note: "Imported \(names.count) validated calibration asset\(names.count == 1 ? "" : "s")."
        )
    }

    private func labelsForName(_ name: String) -> [String] {
        var labels: [String] = []
        if name.contains("spectral") || name.contains("spectrum") {
            labels.append("spectral curves")
        }
        if name.contains("density") || name.contains("hd") || name.contains("h-d") {
            labels.append("density curves")
        }
        if name.contains("grain") || name.contains("granularity") {
            labels.append("grain spectra")
        }
        return labels
    }

    private func kindLabel(_ kind: CalibrationAssetKind) -> String {
        switch kind {
        case .spectral:
            return "spectral curves"
        case .density:
            return "density curves"
        case .grain:
            return "grain spectra"
        }
    }

    private func assetSummary(name: String, labels: [String]) -> String {
        let uniqueLabels = Array(Set(labels)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let detail = uniqueLabels.isEmpty ? "numeric calibration values" : uniqueLabels.joined(separator: ", ")
        return "\(name): \(detail)"
    }

    private func append(
        _ values: [Double],
        named name: String,
        spectral: inout Bool,
        density: inout Bool,
        grain: inout Bool,
        spectralValues: inout [Double],
        densityValues: inout [Double],
        grainValues: inout [Double]
    ) {
        if name.contains("spectral") || name.contains("spectrum") {
            spectral = true
            spectralValues.append(contentsOf: values)
        }
        if name.contains("density") || name.contains("hd") || name.contains("h-d") {
            density = true
            densityValues.append(contentsOf: values)
        }
        if name.contains("grain") || name.contains("granularity") {
            grain = true
            grainValues.append(contentsOf: values)
        }
    }

    private func append(
        _ values: [Double],
        kinds: Set<CalibrationAssetKind>,
        spectral: inout Bool,
        density: inout Bool,
        grain: inout Bool,
        spectralValues: inout [Double],
        densityValues: inout [Double],
        grainValues: inout [Double]
    ) {
        if kinds.contains(.spectral) {
            spectral = true
            spectralValues.append(contentsOf: values)
        }
        if kinds.contains(.density) {
            density = true
            densityValues.append(contentsOf: values)
        }
        if kinds.contains(.grain) {
            grain = true
            grainValues.append(contentsOf: values)
        }
    }

    private func parseCubeCalibration(_ url: URL) throws -> (red: Double, green: Double, blue: Double) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lutSize: Int?
        var rows: [[Double]] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.first?.uppercased() == "LUT_3D_SIZE", parts.count == 2 {
                guard let size = Int(parts[1]), (2...256).contains(size) else {
                    throw CalibrationImportError.invalidAsset(url.lastPathComponent, "LUT_3D_SIZE must be an integer between 2 and 256.")
                }
                lutSize = size
                continue
            }

            let values = parts.compactMap(Double.init)
            guard values.count == parts.count else {
                // Header keywords such as TITLE and DOMAIN_MIN/DOMAIN_MAX are not data rows.
                continue
            }
            if values.count == 3 {
                guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw CalibrationImportError.invalidAsset(url.lastPathComponent, "LUT RGB values must be between 0 and 1.")
                }
                rows.append(values)
                if let lutSize, rows.count > lutSize * lutSize * lutSize {
                    throw CalibrationImportError.invalidAsset(url.lastPathComponent, "Expected \(lutSize * lutSize * lutSize) LUT rows but found more.")
                }
            }
        }

        guard let lutSize, lutSize > 1 else {
            throw CalibrationImportError.invalidAsset(url.lastPathComponent, "Missing valid LUT_3D_SIZE.")
        }
        let expectedRows = lutSize * lutSize * lutSize
        guard rows.count == expectedRows else {
            throw CalibrationImportError.invalidAsset(url.lastPathComponent, "Expected \(expectedRows) LUT rows but found \(rows.count).")
        }

        let totals = rows.reduce((red: 0.0, green: 0.0, blue: 0.0)) { partial, row in
            (partial.red + row[0], partial.green + row[1], partial.blue + row[2])
        }
        let count = Double(rows.count)
        let averages = (red: totals.red / count, green: totals.green / count, blue: totals.blue / count)
        let neutralAverage = max((averages.red + averages.green + averages.blue) / 3.0, 0.001)
        return (
            red: averages.red / neutralAverage,
            green: averages.green / neutralAverage,
            blue: averages.blue / neutralAverage
        )
    }

    private func parseJSONCalibration(_ url: URL) throws -> JSONCalibrationAsset {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let values = numericValues(in: object)
        let lutScale = typedLUTScale(in: object)
        guard !values.isEmpty || lutScale != nil else {
            throw CalibrationImportError.invalidAsset(url.lastPathComponent, "No numeric calibration values found.")
        }
        return JSONCalibrationAsset(
            values: values,
            kinds: calibrationKinds(in: object),
            lutScale: lutScale
        )
    }

    private func parseDelimitedCalibration(_ url: URL) throws -> [Double] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let values = text
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.-+eE").inverted)
            .compactMap(Double.init)
            .filter(\.isFinite)
        guard !values.isEmpty else {
            throw CalibrationImportError.invalidAsset(url.lastPathComponent, "No numeric calibration values found.")
        }
        return values
    }

    private func numericValues(in object: Any) -> [Double] {
        if let number = object as? NSNumber {
            return [number.doubleValue].filter(\.isFinite)
        }
        if let array = object as? [Any] {
            return array.flatMap(numericValues)
        }
        if let dictionary = object as? [String: Any] {
            return dictionary.values.flatMap(numericValues)
        }
        return []
    }

    private func calibrationKinds(in object: Any) -> Set<CalibrationAssetKind> {
        guard let dictionary = object as? [String: Any] else {
            return []
        }

        var rawTypes: [String] = []
        if let assetType = dictionary["asset_type"] as? String ?? dictionary["type"] as? String {
            rawTypes.append(assetType)
        }
        if let assetTypes = dictionary["asset_types"] as? [String] {
            rawTypes.append(contentsOf: assetTypes)
        }

        return Set(rawTypes.compactMap(calibrationKind(for:)))
    }

    private func calibrationKind(for rawType: String) -> CalibrationAssetKind? {
        switch rawType.lowercased() {
        case "spectral", "spectrum", "spectral_curve", "spectral_curves":
            return .spectral
        case "density", "density_curve", "density_curves", "hd", "h-d":
            return .density
        case "grain", "grain_spectrum", "grain_spectra", "granularity":
            return .grain
        default:
            return nil
        }
    }

    private func typedLUTScale(in object: Any) -> (red: Double, green: Double, blue: Double)? {
        guard let dictionary = object as? [String: Any],
              let scale = dictionary["rgb_scale"] as? [String: Any]
        else {
            return nil
        }

        let red = number(in: scale, keys: ["red", "r"])
        let green = number(in: scale, keys: ["green", "g"])
        let blue = number(in: scale, keys: ["blue", "b"])
        guard let red, let green, let blue,
              [red, green, blue].allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            return nil
        }

        return (red, green, blue)
    }

    private func number(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let number = dictionary[key] as? NSNumber {
                return number.doubleValue
            }
            if let string = dictionary[key] as? String,
               let value = Double(string) {
                return value
            }
        }
        return nil
    }

    private func calibrationSignal(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0.5
        }

        let average = values.map(abs).reduce(0, +) / Double(values.count)
        return min(max(average.truncatingRemainder(dividingBy: 1.0), 0), 1)
    }
}
