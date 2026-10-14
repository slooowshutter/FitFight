/** The parts of Apple's and Google's browser sign-in scripts the referral page uses. */
export type AppleSignInSuccess = {
    authorization: { id_token: string };
};

declare global {
    interface Window {
        AppleID?: {
            auth: {
                init(config: {
                    clientId: string;
                    scope: string;
                    redirectURI: string;
                    usePopup: boolean;
                    nonce: string;
                }): void;
            };
        };
        google?: {
            accounts: {
                id: {
                    initialize(config: {
                        client_id: string;
                        nonce: string;
                        callback: (response: { credential: string }) => void;
                    }): void;
                    renderButton(
                        parent: HTMLElement,
                        options: Record<string, string | number>,
                    ): void;
                };
            };
        };
    }
}
