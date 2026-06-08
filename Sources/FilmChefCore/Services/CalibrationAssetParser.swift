import Foundation

package struct CalibrationAssetParser {
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

        for url in urls {
            let name = url.lastPathComponent.lowercased()
            switch url.pathExtension.lowercased() {
            case "cube":
                lutScale = try parseCubeCalibration(url)
                supportsLUT = true
            case "json":
                let values = try parseJSONCalibration(url)
                append(values, named: name, spectral: &supportsSpectral, density: &supportsDensity, grain: &supportsGrain, spectralValues: &spectralValues, densityValues: &densityValues, grainValues: &grainValues)
            case "csv", "txt":
                let values = try parseDelimitedCalibration(url)
                append(values, named: name, spectral: &supportsSpectral, density: &supportsDensity, grain: &supportsGrain, spectralValues: &spectralValues, densityValues: &densityValues, grainValues: &grainValues)
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
            redScale: lutScale.red * (1.0 + spectralBias),
            greenScale: lutScale.green,
            blueScale: lutScale.blue * (1.0 - spectralBias),
            densityGamma: supportsDensity ? 1.0 + (densitySignal * 0.08) : 1.0,
            grainAmount: supportsGrain ? 0.035 + (grainSignal * 0.045) : 0.0,
            note: "Imported \(names.count) validated calibration asset\(names.count == 1 ? "" : "s")."
        )
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
                lutSize = Int(parts[1])
                continue
            }

            let values = parts.compactMap(Double.init)
            if values.count == 3 {
                guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                    throw CalibrationImportError.invalidAsset(url.lastPathComponent, "LUT RGB values must be between 0 and 1.")
                }
                rows.append(values)
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

    private func parseJSONCalibration(_ url: URL) throws -> [Double] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let values = numericValues(in: object)
        guard !values.isEmpty else {
            throw CalibrationImportError.invalidAsset(url.lastPathComponent, "No numeric calibration values found.")
        }
        return values
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

    private func calibrationSignal(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0.5
        }

        let average = values.map(abs).reduce(0, +) / Double(values.count)
        return min(max(average.truncatingRemainder(dividingBy: 1.0), 0), 1)
    }
}
