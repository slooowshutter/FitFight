import Foundation

/// One in-app alert. The backend decides who sees which alert and in which language
/// (web/lib/alerts/in-app-alerts.ts). A button action this build does not know just closes the alert.
struct InAppAlert: Decodable, Identifiable, Equatable {
    struct Choice: Decodable, Equatable {
        let title: String
        /// `update`, `open_character`, `new_fight`, or `dismiss`.
        let action: String
        /// Set for `update`: the App Store, or TestFlight on the beta.
        let url: URL?
        let primary: Bool
    }

    let id: String
    let title: String
    let body: String
    let imageURL: URL?
    let buttons: [Choice]

    enum CodingKeys: String, CodingKey {
        case id, title, body, buttons
        case imageURL = "image_url"
    }
}

struct InAppAlertList: Decodable {
    let alerts: [InAppAlert]
}
