import SwiftUI

struct HypertensionGraphView: View {
    let systolic: Double
    let diastolic: Double

    // Axis ranges to match reference image exactly
    private let diaMin: Double = 40
    private let diaMax: Double = 120
    private let sysMin: Double = 40
    private let sysMax: Double = 180

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 60  // Reserve space for systolic axis
            let height = geometry.size.height - 60  // Reserve space for diastolic axis

            ZStack(alignment: .topLeading) {
                // Background brackets matching reference image exactly
                backgroundBrackets(width: width, height: height)
                    .offset(x: 0, y: 0)

                // Axis labels and values
                axisLabels(width: width, height: height)

                // Plot the reading
                plotPoint(width: width, height: height)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
    }

    // MARK: - Background Brackets

    private func backgroundBrackets(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Stage 2 Hypertension (Red) - Top right, sys≥160 OR dia≥100
            Path { path in
                let sys160Y = mapY(160, height: height)
                let dia100X = mapX(100, width: width)

                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: dia100X, y: height))
                path.addLine(to: CGPoint(x: dia100X, y: sys160Y))
                path.addLine(to: CGPoint(x: 0, y: sys160Y))
                path.closeSubpath()
            }
            .fill(Color(red: 0.98, green: 0.35, blue: 0.35))

            // Border at sys=160 and dia=100
            Path { path in
                let sys160Y = mapY(160, height: height)
                let dia100X = mapX(100, width: width)
                path.move(to: CGPoint(x: 0, y: sys160Y))
                path.addLine(to: CGPoint(x: dia100X, y: sys160Y))
                path.addLine(to: CGPoint(x: dia100X, y: height))
            }
            .stroke(Color.black, lineWidth: 2)

            // Stage 1 Hypertension (Pink) - sys 140-159 OR dia 90-99
            Path { path in
                let sys160Y = mapY(160, height: height)
                let sys140Y = mapY(140, height: height)
                let dia90X = mapX(90, width: width)
                let dia100X = mapX(100, width: width)

                path.move(to: CGPoint(x: 0, y: sys160Y))
                path.addLine(to: CGPoint(x: dia100X, y: sys160Y))
                path.addLine(to: CGPoint(x: dia100X, y: height))
                path.addLine(to: CGPoint(x: dia90X, y: height))
                path.addLine(to: CGPoint(x: dia90X, y: sys140Y))
                path.addLine(to: CGPoint(x: 0, y: sys140Y))
                path.closeSubpath()
            }
            .fill(Color(red: 0.98, green: 0.5, blue: 0.65))

            // Border at sys=140 and dia=90
            Path { path in
                let sys140Y = mapY(140, height: height)
                let dia90X = mapX(90, width: width)
                path.move(to: CGPoint(x: 0, y: sys140Y))
                path.addLine(to: CGPoint(x: dia90X, y: sys140Y))
                path.addLine(to: CGPoint(x: dia90X, y: height))
            }
            .stroke(Color.black, lineWidth: 2)

            // Prehypertension (Orange) - sys 120-139 OR dia 80-89
            Path { path in
                let sys140Y = mapY(140, height: height)
                let sys120Y = mapY(120, height: height)
                let dia80X = mapX(80, width: width)
                let dia90X = mapX(90, width: width)

                path.move(to: CGPoint(x: 0, y: sys140Y))
                path.addLine(to: CGPoint(x: dia90X, y: sys140Y))
                path.addLine(to: CGPoint(x: dia90X, y: height))
                path.addLine(to: CGPoint(x: dia80X, y: height))
                path.addLine(to: CGPoint(x: dia80X, y: sys120Y))
                path.addLine(to: CGPoint(x: 0, y: sys120Y))
                path.closeSubpath()
            }
            .fill(Color(red: 0.95, green: 0.65, blue: 0.35))

            // Border at sys=120 and dia=80
            Path { path in
                let sys120Y = mapY(120, height: height)
                let dia80X = mapX(80, width: width)
                path.move(to: CGPoint(x: 0, y: sys120Y))
                path.addLine(to: CGPoint(x: dia80X, y: sys120Y))
                path.addLine(to: CGPoint(x: dia80X, y: height))
            }
            .stroke(Color.black, lineWidth: 2)

            // Normal (Green) - sys 90-119 AND dia 60-79, PLUS fill the Low space
            // This creates a single green area that extends all the way to bottom-left
            Path { path in
                let sys120Y = mapY(120, height: height)
                let dia80X = mapX(80, width: width)

                // Draw from top-left of Normal zone, going around to include the Low area
                path.move(to: CGPoint(x: 0, y: sys120Y))
                path.addLine(to: CGPoint(x: dia80X, y: sys120Y))
                path.addLine(to: CGPoint(x: dia80X, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(Color(red: 0.45, green: 0.85, blue: 0.45))

            // Border between Low and Normal zones
            Path { path in
                let sys90Y = mapY(90, height: height)
                let dia60X = mapX(60, width: width)

                path.move(to: CGPoint(x: dia60X, y: sys90Y))
                path.addLine(to: CGPoint(x: dia60X, y: height))
                path.move(to: CGPoint(x: 0, y: sys90Y))
                path.addLine(to: CGPoint(x: dia60X, y: sys90Y))
            }
            .stroke(Color.black, lineWidth: 2)

            // Low (Cyan) - Overlay on the left portion
            Path { path in
                let sys90Y = mapY(90, height: height)
                let dia60X = mapX(60, width: width)

                path.move(to: CGPoint(x: 0, y: sys90Y))
                path.addLine(to: CGPoint(x: dia60X, y: sys90Y))
                path.addLine(to: CGPoint(x: dia60X, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(Color(red: 0.4, green: 0.85, blue: 0.85))
        }
    }

    // MARK: - Axis Labels

    private func axisLabels(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Zone labels - left-aligned with consistent padding from left edge
            let labelPadding: CGFloat = 45

            // Calculate vertical centers of each zone
            let stage2CenterY = mapY(170, height: height)  // Between 160-180
            let stage1CenterY = mapY(150, height: height)  // Between 140-160
            let prehyperCenterY = mapY(130, height: height) // Between 120-140
            let normalCenterY = mapY(105, height: height)  // Between 90-120
            let lowCenterY = mapY(65, height: height)      // Between 40-90

            HStack {
                Text("High: Stage 2 Hypertension")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .offset(x: labelPadding)
            .position(x: width / 2, y: stage2CenterY)

            HStack {
                Text("High: Stage 1 Hypertension")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .offset(x: labelPadding)
            .position(x: width / 2, y: stage1CenterY)

            HStack {
                Text("Prehypertension")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .offset(x: labelPadding)
            .position(x: width / 2, y: prehyperCenterY)

            HStack {
                Text("Normal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .offset(x: labelPadding)
            .position(x: width / 2, y: normalCenterY)

            HStack {
                Text("Low")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .offset(x: labelPadding)
            .position(x: width / 2, y: lowCenterY)

            // Diastolic axis (bottom)
            ForEach([40, 60, 80, 90, 100, 120], id: \.self) { dia in
                Text("\(dia)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .position(x: mapX(Double(dia), width: width), y: height + 20)
            }

            // Diastolic label (bottom center) with more spacing
            Text("Diastolic (mmHg)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .position(x: width / 2, y: height + 45)

            // Systolic axis (right)
            ForEach([40, 60, 80, 90, 100, 120, 140, 160, 180], id: \.self) { sys in
                Text("\(sys)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .position(x: width + 25, y: mapY(Double(sys), height: height))
            }

            // Systolic label (right side, rotated)
            Text("Systolic (mmHg)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .position(x: width + 50, y: height / 2)
        }
    }

    // MARK: - Plot Point

    private func plotPoint(width: CGFloat, height: CGFloat) -> some View {
        let clampedDia = min(max(diastolic, diaMin), diaMax)
        let clampedSys = min(max(systolic, sysMin), sysMax)

        let x = mapX(clampedDia, width: width)
        let y = mapY(clampedSys, height: height)

        return Circle()
            .fill(.black)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .strokeBorder(.white, lineWidth: 3.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .position(x: x, y: y)
    }

    // MARK: - Coordinate Mapping

    private func mapX(_ diastolic: Double, width: CGFloat) -> CGFloat {
        let normalized = (diastolic - diaMin) / (diaMax - diaMin)
        return CGFloat(normalized) * width
    }

    private func mapY(_ systolic: Double, height: CGFloat) -> CGFloat {
        let normalized = (systolic - sysMin) / (sysMax - sysMin)
        return height - (CGFloat(normalized) * height)
    }
}

#Preview {
    HypertensionGraphView(systolic: 145, diastolic: 92)
        .padding(40)
        .frame(width: 400, height: 400)
        .background(Color.gray.opacity(0.2))
}
