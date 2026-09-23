import type {
    startBlendWorkflow,
    readBlendWorkflowRun,
} from "@/lib/blend/client";
import type {
    reserveAiRequest,
    claimAiRequestPoll,
    finishAiRequestAttempt,
    markAiSubmission,
} from "@/lib/supabase/queries/ai-requests-supabase-query";

export type AiRequestDependencies = {
    reserve: typeof reserveAiRequest;
    claim: typeof claimAiRequestPoll;
    finish: typeof finishAiRequestAttempt;
    submit: typeof markAiSubmission;
    start: typeof startBlendWorkflow;
    read: typeof readBlendWorkflowRun;
};

export type AiReconciliationDependencies = {
    due: typeof import("@/lib/supabase/queries/ai-requests-supabase-query").dueAiRequests;
    read: typeof import("@/lib/domain/ai/workflow-requests").readAiRun;
    pruneLogs: typeof import("@/lib/supabase/queries/ai-http-logs-supabase-query").insertAiHttpLogs;
};
