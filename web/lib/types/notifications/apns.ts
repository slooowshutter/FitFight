export type ApnsSendInput = {
    deviceToken: string;
    environment: "sandbox" | "production";
    topic: string;
    title: string;
    body: string;
    route: string;
    threadId?: string;
    collapseId?: string;
    expiresAt?: number;
    imageUrl?: string;
};

export type ApnsSendResult = {
    httpStatus: number;
    reason: string | null;
    apnsId: string | null;
    unregistered: boolean;
    retryLater: boolean;
    invalidProviderToken: boolean;
};
