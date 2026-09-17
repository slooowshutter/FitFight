import { feedbackWorkflowEnvironmentSchema } from "@/lib/types/feedback/feedback";

/** The rollout switch also keeps nullable-author writes off while old readers drain. */
export function feedbackWorkflowAccess(userId: string) {
    const config = feedbackWorkflowEnvironmentSchema.parse(process.env);
    return {
        enabled: config.FITFIGHT_FEEDBACK_WORKFLOW_ENABLED === "true",
        isAdmin: userId === config.FITFIGHT_FEEDBACK_ADMIN_USER_ID,
    };
}
