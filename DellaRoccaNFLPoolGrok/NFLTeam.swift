import Foundation
import SwiftUI

/// One official color for an NFL team, in palette order: primary, then secondary, then tertiary when the team has one.
struct TeamColor: Hashable, Identifiable {
    enum Slot: String, Hashable, Identifiable {
        case primary
        case secondary
        case tertiary

        var id: String { rawValue }
    }

    let teamName: String
    let slot: Slot
    let name: String
    let hex: String

    var id: Slot { slot }

    /// Matches the namespaced color set `NFL Team Colors/<team>/<color name>`.
    var assetName: String { "NFL Team Colors/\(teamName)/\(name)" }

    var color: Color {
        Color(assetName)
    }

    /// Text color that stays readable when drawn on `color`.
    var foreground: Color {
        relativeLuminance > 0.179 ? .black : .white
    }

    fileprivate init(teamName: String, slot: Slot, name: String, hex: String) {
        let digits = hex.filter(\.isHexDigit).uppercased()
        precondition(digits.count == 6, "Team color hex must be RRGGBB, got \(hex)")
        self.teamName = teamName
        self.slot = slot
        self.name = name
        self.hex = "#" + digits
    }

    private var components: (red: Double, green: Double, blue: Double) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        let (red, green, blue) = components
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

struct NFLTeam: Identifiable, Hashable {
    let abbreviation: String
    let name: String
    let colors: [TeamColor]

    var id: String { abbreviation }

    var primaryColor: TeamColor { colors[0] }
    var secondaryColor: TeamColor { colors[1] }
    var tertiaryColor: TeamColor? { colors.count > 2 ? colors[2] : nil }

    init(abbreviation: String, name: String, colors listed: [(name: String, hex: String)]) {
        precondition((2 ... 3).contains(listed.count), "\(name) needs 2 or 3 colors")
        precondition(Set(listed.map(\.name)).count == listed.count, "\(name) has duplicate color names")
        let slots: [TeamColor.Slot] = [.primary, .secondary, .tertiary]
        self.abbreviation = abbreviation
        self.name = name
        self.colors = zip(slots, listed).map { slot, entry in
            TeamColor(teamName: name, slot: slot, name: entry.name, hex: entry.hex)
        }
    }
}

extension NFLTeam {
    /// Colors are the official team colors from NFL_Teams_Colors_Stadiums.csv.
    static let all: [NFLTeam] = {
        let teams = catalog
        precondition(teams.count == 32, "Expected 32 NFL teams")
        precondition(Set(teams.map(\.abbreviation)).count == teams.count, "Team abbreviations must be unique")
        return teams
    }()

    static let byAbbreviation: [String: NFLTeam] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.abbreviation, $0) }
    )

    static func team(abbreviation: String) -> NFLTeam? {
        byAbbreviation[abbreviation.uppercased()]
    }

    private static let catalog: [NFLTeam] = [
        NFLTeam(abbreviation: "ARI", name: "Arizona Cardinals", colors: [
            (name: "Cardinal Red", hex: "#97233F"),
            (name: "Black", hex: "#000000"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "ATL", name: "Atlanta Falcons", colors: [
            (name: "Red", hex: "#A71930"),
            (name: "Black", hex: "#000000"),
            (name: "Silver", hex: "#A5ACAF"),
        ]),
        NFLTeam(abbreviation: "BAL", name: "Baltimore Ravens", colors: [
            (name: "Purple", hex: "#241773"),
            (name: "Black", hex: "#000000"),
            (name: "Metallic Gold", hex: "#9E7C0C"),
        ]),
        NFLTeam(abbreviation: "BUF", name: "Buffalo Bills", colors: [
            (name: "Royal Blue", hex: "#00338D"),
            (name: "Red", hex: "#C60C30"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "CAR", name: "Carolina Panthers", colors: [
            (name: "Panther Blue", hex: "#0085CA"),
            (name: "Black", hex: "#101820"),
            (name: "Silver", hex: "#BFC0BF"),
        ]),
        NFLTeam(abbreviation: "CHI", name: "Chicago Bears", colors: [
            (name: "Navy Blue", hex: "#0B162A"),
            (name: "Orange", hex: "#C83803"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "CIN", name: "Cincinnati Bengals", colors: [
            (name: "Orange", hex: "#FB4F14"),
            (name: "Black", hex: "#000000"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "CLE", name: "Cleveland Browns", colors: [
            (name: "Brown", hex: "#311D00"),
            (name: "Orange", hex: "#FF3C00"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "DAL", name: "Dallas Cowboys", colors: [
            (name: "Navy Blue", hex: "#003594"),
            (name: "Silver", hex: "#869397"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "DEN", name: "Denver Broncos", colors: [
            (name: "Orange", hex: "#FB4F14"),
            (name: "Navy Blue", hex: "#002244"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "DET", name: "Detroit Lions", colors: [
            (name: "Honolulu Blue", hex: "#0076B6"),
            (name: "Silver", hex: "#B0B7BC"),
            (name: "Black", hex: "#000000"),
        ]),
        NFLTeam(abbreviation: "GB", name: "Green Bay Packers", colors: [
            (name: "Dark Green", hex: "#203731"),
            (name: "Gold", hex: "#FFB612"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "HOU", name: "Houston Texans", colors: [
            (name: "Deep Steel Blue", hex: "#03202F"),
            (name: "Battle Red", hex: "#A71930"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "IND", name: "Indianapolis Colts", colors: [
            (name: "Speed Blue", hex: "#002C5F"),
            (name: "White", hex: "#FFFFFF"),
            (name: "Gray", hex: "#A5ACAF"),
        ]),
        NFLTeam(abbreviation: "JAX", name: "Jacksonville Jaguars", colors: [
            (name: "Teal", hex: "#006778"),
            (name: "Black", hex: "#101820"),
            (name: "Gold", hex: "#D7A22A"),
        ]),
        NFLTeam(abbreviation: "KC", name: "Kansas City Chiefs", colors: [
            (name: "Red", hex: "#E31837"),
            (name: "Gold", hex: "#FFB81C"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "LV", name: "Las Vegas Raiders", colors: [
            (name: "Silver", hex: "#A5ACAF"),
            (name: "Black", hex: "#000000"),
        ]),
        NFLTeam(abbreviation: "LAC", name: "Los Angeles Chargers", colors: [
            (name: "Powder Blue", hex: "#0080C6"),
            (name: "Gold", hex: "#FFC20E"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "LAR", name: "Los Angeles Rams", colors: [
            (name: "Royal Blue", hex: "#003594"),
            (name: "Sol", hex: "#FFA300"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "MIA", name: "Miami Dolphins", colors: [
            (name: "Aqua", hex: "#008E97"),
            (name: "Orange", hex: "#FC4C02"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "MIN", name: "Minnesota Vikings", colors: [
            (name: "Purple", hex: "#4F2683"),
            (name: "Gold", hex: "#FFC62F"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "NE", name: "New England Patriots", colors: [
            (name: "Nautical Blue", hex: "#002244"),
            (name: "Red", hex: "#C60C30"),
            (name: "Silver", hex: "#B0B7BC"),
        ]),
        NFLTeam(abbreviation: "NO", name: "New Orleans Saints", colors: [
            (name: "Old Gold", hex: "#D3BC8D"),
            (name: "Black", hex: "#101820"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "NYG", name: "New York Giants", colors: [
            (name: "Blue", hex: "#0B2265"),
            (name: "Red", hex: "#A71930"),
            (name: "White", hex: "#FFFFFF"),
        ]),
        NFLTeam(abbreviation: "NYJ", name: "New York Jets", colors: [
            (name: "Gotham Green", hex: "#125740"),
            (name: "White", hex: "#FFFFFF"),
            (name: "Black", hex: "#000000"),
        ]),
        NFLTeam(abbreviation: "PHI", name: "Philadelphia Eagles", colors: [
            (name: "Midnight Green", hex: "#004C54"),
            (name: "Silver", hex: "#A5ACAF"),
            (name: "Black", hex: "#000000"),
        ]),
        NFLTeam(abbreviation: "PIT", name: "Pittsburgh Steelers", colors: [
            (name: "Black", hex: "#101820"),
            (name: "Gold", hex: "#FFB612"),
        ]),
        NFLTeam(abbreviation: "SF", name: "San Francisco 49ers", colors: [
            (name: "49ers Red", hex: "#AA0000"),
            (name: "Gold", hex: "#B3995D"),
        ]),
        NFLTeam(abbreviation: "SEA", name: "Seattle Seahawks", colors: [
            (name: "College Navy", hex: "#002244"),
            (name: "Action Green", hex: "#69BE28"),
            (name: "Wolf Grey", hex: "#A5ACAF"),
        ]),
        NFLTeam(abbreviation: "TB", name: "Tampa Bay Buccaneers", colors: [
            (name: "Buccaneer Red", hex: "#D50A0A"),
            (name: "Pewter", hex: "#34302B"),
            (name: "Orange", hex: "#FF7900"),
        ]),
        NFLTeam(abbreviation: "TEN", name: "Tennessee Titans", colors: [
            (name: "Navy", hex: "#0C2340"),
            (name: "Titans Blue", hex: "#4B92DB"),
            (name: "Red", hex: "#C8102E"),
        ]),
        NFLTeam(abbreviation: "WAS", name: "Washington Commanders", colors: [
            (name: "Burgundy", hex: "#5A1414"),
            (name: "Gold", hex: "#FFB612"),
            (name: "White", hex: "#FFFFFF"),
        ]),
    ]
}
