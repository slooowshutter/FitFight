export const googleOAuthClients = {
    "zstzbfocunthczzubggz.supabase.co": {
        iosClientID:
            "428975685987-6j9128tgf2k67pkf5tlsdbs58md0b38u.apps.googleusercontent.com",
        webClientID:
            "428975685987-i4dlh5lj59foo21p40pvmmnea5glipac.apps.googleusercontent.com",
    },
    "pvqntpteehdvhqyctwum.supabase.co": {
        iosClientID:
            "1060235196761-nuoouoc4envuhkpo4kpdfpdg8u20tlq4.apps.googleusercontent.com",
        webClientID:
            "1060235196761-uo86cnhqd7rp1oms7islaq4u4vd71vek.apps.googleusercontent.com",
    },
} as const;

export type GoogleOAuthClients =
    (typeof googleOAuthClients)[keyof typeof googleOAuthClients];

export function googleOAuthClientsForProject(
    projectURL: string,
): GoogleOAuthClients | null {
    let host: string;
    try {
        host = new URL(projectURL).hostname;
    } catch {
        return null;
    }
    return googleOAuthClients[host as keyof typeof googleOAuthClients] ?? null;
}
