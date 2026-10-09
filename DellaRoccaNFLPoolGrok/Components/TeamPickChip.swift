import SwiftUI

struct TeamPickChip: View {
    let abbreviation: String
    let selected: Bool
    let dimmed: Bool
    var logoURL: URL?

    var body: some View {
        let team = NFLTeam.team(abbreviation: abbreviation)
        VStack(spacing: 3) {
            if let logoURL {
                AsyncImage(request: logoRequest(logoURL)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
//                .frame(width: 60, height: 60)
            }
        }
//        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .background(.linearGradient(colors: [team?.primaryColor.color ?? .gray, team?.secondaryColor.color ?? .gray],startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 6))
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

    /// Team logos are a fixed, immutable set. Serving them from cache without
    /// re-validation avoids reloading and flicker as rows recycle in a list.
    private func logoRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        return request
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
