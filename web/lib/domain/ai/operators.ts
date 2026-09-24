import { ApiError } from "@/lib/http";
import { aiOperatorConfigurationSchema } from "@/lib/types/ai/credits";

/** Authorization uses the verified Auth ID and server configuration, never editable user metadata. */
export function requireAiOperator(userId: string) {
    const config = aiOperatorConfigurationSchema.parse(process.env);
    if (config.FITFIGHT_ADMIN_USER_ID?.toLowerCase() !== userId.toLowerCase()) {
        throw new ApiError(
            403,
            "forbidden",
            "This action requires an authorized operator.",
        );
    }
}
