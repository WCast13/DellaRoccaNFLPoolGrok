import SwiftUI

struct TeamPickChip: View {
    let abbreviation: String
    let selected: Bool
    let dimmed: Bool
    var logoURL: URL?
    /// Edge length of the square chip.
    ///
    /// The chip owns its own geometry rather than relying on each caller to add
    /// a frame. An unconstrained `AsyncImage` has no intrinsic size, so inside a
    /// horizontal `ScrollView` — which proposes nil width — a caller that forgot
    /// one rendered the placeholder at roughly 10pt and then jumped to the
    /// logo's native 500pt once the image landed.
    var size: CGFloat = 60

    var body: some View {
        let team = NFLTeam.team(abbreviation: abbreviation)
        VStack(spacing: 3) {
            if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .background(.linearGradient(colors: [team?.primaryColor.color ?? .gray, team?.secondaryColor.color ?? .gray],startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6))
        .frame(width: size, height: size)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.green, lineWidth: 2)
            }
        }
//        .overlay(alignment: .topTrailing) {
//            if selected {
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.caption)
//                    .foregroundStyle(.green)
//                    .background(Circle().fill(.background))
//            }
//        }
        .opacity(dimmed ? 0.3 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Pick chips") {
    HStack(spacing: 8) {
        TeamPickChip(abbreviation: "JAX", selected: true, dimmed: false, logoURL: PreviewData.logos["JAX"])
        TeamPickChip(abbreviation: "SF", selected: false, dimmed: true, logoURL: PreviewData.logos["SF"])
        TeamPickChip(abbreviation: "DAL", selected: false, dimmed: true, logoURL: PreviewData.logos["DAL"])
    }
    .padding()
}
#endif
