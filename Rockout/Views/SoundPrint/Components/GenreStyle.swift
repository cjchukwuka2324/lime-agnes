import SwiftUI

enum GenreStyle {

    static func color(for genre: String) -> Color {
        let key = genre.lowercased()

        if key.contains("hip hop") || key.contains("rap") {
            return Color.purple
        }
        if key.contains("trap") {
            return Color.pink
        }
        if key.contains("afrobeats") || key.contains("afrobeat") || key.contains("afro") {
            return Color.orange
        }
        if key.contains("r&b") || key.contains("rnb") {
            return Color.indigo
        }
        if key.contains("pop") {
            return Color.blue
        }
        if key.contains("house") || key.contains("dance") || key.contains("edm") {
            return Color.cyan
        }
        if key.contains("rock") {
            return Color.red
        }
        return Color.white
    }

    static func emoji(for genre: String) -> String {
        let key = genre.lowercased()

        if key.contains("hip hop") || key.contains("rap") { return "🎤" }
        if key.contains("trap") { return "🔥" }
        if key.contains("afro") { return "🌍" }
        if key.contains("r&b") || key.contains("rnb") { return "💜" }
        if key.contains("pop") { return "✨" }
        if key.contains("house") || key.contains("dance") || key.contains("edm") { return "💿" }
        if key.contains("rock") { return "🎸" }
        return "🎧"
    }
}
