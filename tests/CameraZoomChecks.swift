
let triple = CameraZoomConfiguration.choices(minimum: 0.5, maximum: 10, native: [1, 5])
precondition(triple == [0.5, 1, 2, 5], "Triple-camera shortcuts changed")
precondition(CameraZoomConfiguration.choices(minimum: 1, maximum: 1, native: []) == [1])
precondition(CameraZoomConfiguration.choices(minimum: 1, maximum: 3, native: [1, 3, 5]) == [1, 2, 3])
for minimum in [0.5, 1.0, 2.0] {
    for maximum in [3.0, 5.0, 10.0] {
        for value in [-100.0, 0, 0.5, 1, 2, 5, 100, .nan, .infinity, -.infinity] {
            let result = CameraZoomConfiguration.clamp(value, minimum: minimum, maximum: maximum)
            precondition(result.isFinite && result >= minimum && result <= maximum)
        }
        let choices = CameraZoomConfiguration.choices(minimum: minimum, maximum: maximum, native: [1, 3, 5])
        precondition(choices == choices.sorted() && Set(choices).count == choices.count)
        precondition(choices.allSatisfy { $0 >= minimum && $0 <= maximum })
    }
}
print("PASS: hardware-dependent zoom shortcuts, single-lens fallback, zoom bounds and nonfinite input")
