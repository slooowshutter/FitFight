import { fightAdminConfigurationSchema } from "@/lib/types/admin/fight-administration";

/** Fight administration trusts only the environment's immutable Auth user ID. */
export function canAdministerFights(userId: string): boolean {
    const configured = fightAdminConfigurationSchema.parse({ user_id: process.env.FITFIGHT_ADMIN_USER_ID });
    return configured.user_id?.toLowerCase() === userId.toLowerCase();
}
