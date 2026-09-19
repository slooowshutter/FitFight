import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import {
    profileDatabaseRowSchema,
    type Profile,
    type ProfileDatabaseRow,
    type UpdateProfileRequest,
} from "@/lib/types/profiles/profile";
import {
    loadReadyMedia,
    mapMedia,
    signMediaUrl,
    type MediaRow,
} from "./media-supabase-query";

const PROFILE_COLUMNS =
    "id, handle, display_name, handle_set_at, referral_code, avatar_media_id, companion_id, companion_prompt, time_zone";

async function asProfile(
    row: ProfileDatabaseRow,
    admin: SupabaseClient,
): Promise<Profile> {
    let avatar = null;
    if (row.avatar_media_id) {
        const { data, error } = await admin
            .from("media_objects")
            .select(
                "id, owner_id, kind, purpose, status, object_path, original_filename, content_type, byte_size, width, height, duration_ms, sha256, created_at",
            )
            .eq("id", row.avatar_media_id)
            .eq("status", "ready")
            .maybeSingle();
        if (error)
            throw new ApiError(500, "db_error", "Could not load profile photo");
        if (data) {
            const media = data as MediaRow;
            avatar = mapMedia(media, await signMediaUrl(media.object_path));
        }
    }
    return {
        user_id: row.id,
        handle: row.handle,
        display_name: row.display_name,
        handle_set_at: row.handle_set_at,
        referral_code: row.referral_code,
        avatar,
        companion_id: row.companion_id,
        companion_prompt: row.companion_prompt,
        time_zone: row.time_zone ?? "UTC",
    };
}

export async function readProfile(
    userId: string,
    admin: SupabaseClient = createAdminClient(),
): Promise<Profile> {
    const { data, error } = await admin
        .from("profiles")
        .select(PROFILE_COLUMNS)
        .eq("id", userId)
        .is("deleted_at", null)
        .maybeSingle();
    if (error) throw new ApiError(500, "db_error", "Could not load profile");
    if (!data)
        throw new ApiError(
            401,
            "profile_missing",
            "Invalid or deleted account",
        );
    return asProfile(profileDatabaseRowSchema.parse(data), admin);
}

export async function updateProfile(
    userId: string,
    input: UpdateProfileRequest,
    admin: SupabaseClient = createAdminClient(),
): Promise<Profile> {
    if (input.avatar_media_id) {
        const media = await loadReadyMedia(
            userId,
            [input.avatar_media_id],
            "profile",
        );
        if (media.length !== 1) {
            throw new ApiError(
                400,
                "validation",
                "Upload a profile photo first",
            );
        }
    }
    const { data, error } = await admin
        .from("profiles")
        .update({
            ...(input.handle !== undefined
                ? {
                      handle: input.handle,
                      handle_set_at: new Date().toISOString(),
                  }
                : {}),
            ...(input.display_name !== undefined
                ? { display_name: input.display_name }
                : {}),
            ...(input.time_zone !== undefined
                ? { time_zone: input.time_zone }
                : {}),
            ...(input.avatar_media_id !== undefined
                ? { avatar_media_id: input.avatar_media_id }
                : {}),
            ...(input.companion_id !== undefined
                ? {
                      companion_id: input.companion_id,
                      companion_prompt:
                          input.companion_id === "custom"
                              ? input.companion_prompt
                              : null,
                  }
                : input.companion_prompt !== undefined
                  ? { companion_prompt: input.companion_prompt }
                  : {}),
        })
        .eq("id", userId)
        .is("deleted_at", null)
        .select(PROFILE_COLUMNS)
        .maybeSingle();
    if (error?.code === "23505")
        throw new ApiError(409, "handle_taken", "That username is taken");
    if (error?.code === "23514")
        throw new ApiError(400, "validation", "Choose a companion");
    if (error) throw new ApiError(500, "db_error", "Could not update profile");
    if (!data)
        throw new ApiError(
            401,
            "profile_missing",
            "Invalid or deleted account",
        );
    return asProfile(profileDatabaseRowSchema.parse(data), admin);
}
