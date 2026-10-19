import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { readAiCompanionImage } from "./ai-library-supabase-query";
import { readCompanionLabel } from "./custom-characters-supabase-query";
import {
    profileDatabaseRowSchema,
    type Profile,
    type ProfileDatabaseRow,
    type UpdateProfileRequest,
} from "@/lib/types/profiles/profile";

const PROFILE_COLUMNS =
    "id, handle, display_name, handle_set_at, referral_code, companion_id, companion_prompt, companion_image_url, time_zone";

async function asProfile(row: ProfileDatabaseRow): Promise<Profile> {
    return {
        user_id: row.id,
        handle: row.handle,
        display_name: row.display_name,
        handle_set_at: row.handle_set_at,
        referral_code: row.referral_code,
        // Your companion is your only picture: an uploaded photo is never shown.
        avatar: null,
        companion_id: row.companion_id,
        companion_prompt: row.companion_prompt,
        ...(row.companion_id === "custom" && row.companion_image_url
            ? {
                  companion_image_url: row.companion_image_url,
                  ...(await readCompanionLabel(row.id, row.companion_image_url)),
              }
            : {}),
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
    return asProfile(profileDatabaseRowSchema.parse(data));
}

export async function updateProfile(
    userId: string,
    input: UpdateProfileRequest,
    admin: SupabaseClient = createAdminClient(),
): Promise<Profile> {
    const image = input.companion_image
        ? await readAiCompanionImage(userId, input.companion_image)
        : null;
    if (input.avatar_media_id) {
        throw new ApiError(
            400,
            "validation",
            "Profile photos are gone. Your companion is your profile picture.",
        );
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
            ...(image
                ? {
                      companion_id: "custom",
                      companion_prompt: image.description,
                      companion_image_url: image.image_url,
                  }
                : input.avatar_media_id !== undefined ||
                    input.companion_id !== undefined ||
                    input.companion_prompt !== undefined
                  ? { companion_image_url: null }
                  : {}),
        })
        .eq("id", userId)
        .is("deleted_at", null)
        .select(PROFILE_COLUMNS)
        .maybeSingle();
    if (
        error?.code === "P0001" &&
        error.message.includes("special_purchase_required")
    )
        throw new ApiError(
            403,
            "special_purchase_required",
            "Purchase this Special before using it",
        );
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
    return asProfile(profileDatabaseRowSchema.parse(data));
}
