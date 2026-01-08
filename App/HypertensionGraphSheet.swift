import SwiftUI

struct HypertensionGraphSheet: View {
    let systolic: Double
    let diastolic: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Numeric reading display
                VStack(spacing: 8) {
                    Text("\(Int(systolic))/\(Int(diastolic)) mmHg")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Your Blood Pressure Reading")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                // Graph
                HypertensionGraphView(systolic: systolic, diastolic: diastolic)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 400)

                Spacer()
            }
            .navigationTitle("Blood Pressure Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
    }
}

#Preview {
    HypertensionGraphSheet(systolic: 145, diastolic: 92)
}
