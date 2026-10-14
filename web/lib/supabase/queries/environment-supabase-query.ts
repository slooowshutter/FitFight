import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    environmentNameSchema,
    type EnvironmentName,
} from "@/lib/types/environment/environment";

export async function readEnvironment(
    projectRef: string,
    database: Sql = createDatabaseClient(),
): Promise<EnvironmentName> {
    const [row] = await database`
        select name from private.environments where project_ref = ${projectRef}
    `;
    if (!row) {
        throw new ApiError(
            503,
            ERROR_CODES.config,
            "Environment is not configured",
        );
    }
    return environmentNameSchema.parse(row.name);
}
