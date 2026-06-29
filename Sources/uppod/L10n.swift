import Foundation

enum L10n {
    private static var isTurkish: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true
    }

    static func text(_ tr: String, _ en: String) -> String {
        isTurkish ? tr : en
    }

    static func shortDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if isTurkish {
            if h > 0 { return "\(h) sa \(m) dk" }
            if m > 0 { return "\(m) dk \(s) sn" }
            return "\(s) sn"
        }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    static func stateLabel(_ state: PostureState) -> String {
        switch state {
        case .good: return text("Dik duruş", "Upright")
        case .slight: return text("Hafif eğim", "Slight lean")
        case .poor: return text("Kambur duruş", "Slouching")
        case .paused: return text("Duraklatıldı", "Paused")
        }
    }

    static func scoreBand(_ score: Int) -> String {
        switch score {
        case 85...: return text("Mükemmel", "Excellent")
        case 70..<85: return text("İyi", "Good")
        case 50..<70: return text("Dikkat", "Careful")
        default: return text("Zor gün", "Rough day")
        }
    }

    static func sensitivityLabel(_ value: Double) -> String {
        if value < 0.9 { return text("Rahat", "Relaxed") }
        if value > 1.2 { return text("Sıkı", "Strict") }
        return text("Normal", "Normal")
    }

    static func exerciseName(id: String, fallback: String) -> String {
        switch id {
        case "flexion": return text("Yukarı aşağı", "Look up & down")
        case "roll": return text("Yan esneme", "Side tilt")
        case "chintuck": return text("Çene geriye", "Chin tuck")
        case "yaw": return text("Sağa sola bak", "Look left & right")
        default: return fallback
        }
    }

    static func exerciseInstruction(id: String, fallback: String) -> String {
        switch id {
        case "flexion":
            return text(
                "Başını yavaşça göğsüne indir, sonra yukarı kaldır.",
                "Slowly lower your head toward your chest, then lift it up."
            )
        case "roll":
            return text(
                "Sol ve sağ omzuna doğru yavaşça eğil.",
                "Slowly tilt toward your left and right shoulder."
            )
        case "chintuck":
            return text(
                "Çeneni düz şekilde geriye al ve tut.",
                "Draw your chin straight back and hold."
            )
        case "yaw":
            return text(
                "Omuzunun üzerinden bakacak kadar yavaşça dön.",
                "Slowly turn far enough to look over your shoulder."
            )
        default:
            return fallback
        }
    }
}

