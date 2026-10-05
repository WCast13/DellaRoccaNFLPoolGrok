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
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 22, height: 22)
            }
            Text(team?.shortName ?? abbreviation)
                .font(.caption.weight(.bold))
                .foregroundStyle(team?.primaryColor.foreground ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(abbreviation)
                .font(.caption2)
                .foregroundStyle(team?.primaryColor.foreground ?? .white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(team?.primaryColor.color ?? .gray, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary, lineWidth: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .background(Circle().fill(.background))
                    .padding(2)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
