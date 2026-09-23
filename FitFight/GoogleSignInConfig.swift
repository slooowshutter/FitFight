import Foundation
import GoogleSignIn

enum GoogleSignInConfig {
    /// TestFlight uses Release with staging BuildEnv, so follow Auth's actual project.
    static func configuration(for projectURL: URL) -> GIDConfiguration? {
        switch projectURL.host {
        case "zstzbfocunthczzubggz.supabase.co":
            return GIDConfiguration(
                clientID: "428975685987-6j9128tgf2k67pkf5tlsdbs58md0b38u.apps.googleusercontent.com",
                serverClientID: "428975685987-i4dlh5lj59foo21p40pvmmnea5glipac.apps.googleusercontent.com"
            )
        case "pvqntpteehdvhqyctwum.supabase.co":
            return GIDConfiguration(
                clientID: "1060235196761-nuoouoc4envuhkpo4kpdfpdg8u20tlq4.apps.googleusercontent.com",
                serverClientID: "1060235196761-uo86cnhqd7rp1oms7islaq4u4vd71vek.apps.googleusercontent.com"
            )
        default:
            return nil
        }
    }
}
