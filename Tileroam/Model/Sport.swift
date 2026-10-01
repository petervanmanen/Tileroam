import Foundation

/// Display helpers for the sport names stored on activities ("Cycling", "Running", …).
enum Sport {
    static func name(_ sport: String) -> String {
        switch sport {
        case "Cycling": String(localized: "Cycling")
        case "E-biking": String(localized: "E-biking")
        case "Running": String(localized: "Running")
        case "Walking": String(localized: "Walking")
        case "Hiking": String(localized: "Hiking")
        case "Swimming": String(localized: "Swimming")
        case "Skiing": String(localized: "Skiing")
        case "Rowing": String(localized: "Rowing")
        case "Inline skating": String(localized: "Inline skating")
        case "Fitness": String(localized: "Fitness")
        default: String(localized: "Other")
        }
    }

    static func symbol(_ sport: String) -> String {
        switch sport {
        case "Cycling": "bicycle"
        case "E-biking": "bolt.circle"
        case "Running": "figure.run"
        case "Walking": "figure.walk"
        case "Hiking": "figure.hiking"
        case "Swimming": "figure.pool.swim"
        case "Skiing": "figure.skiing.downhill"
        case "Rowing": "figure.rower"
        case "Inline skating": "figure.skating"
        case "Fitness": "dumbbell"
        default: "figure.mixed.cardio"
        }
    }
}
