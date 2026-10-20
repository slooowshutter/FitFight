begin;

-- Supabase stops auto-granting Data API privileges on new public tables on 30 Oct 2026.
-- These statements restate the privileges the app already has, so a database created
-- without that default can still reach the same rows. They do not change policies.
-- anon gets nothing: no screen reads or writes the Data API while signed out.
-- private stays off the Data API. whoop_connections, snake_scores, fight_group_images,
-- alert_responses, and app_error_logs are private and stay revoked. The server writes
-- them with the database owner, not service_role.

grant all on table
    public.profiles,
    public.friendships,
    public.fights,
    public.data_sources,
    public.fight_members,
    public.fight_invites,
    public.step_days,
    public.metric_days,
    public.feedback_posts,
    public.feedback_votes,
    public.feedback_comments,
    public.feedback_post_media,
    public.fight_series,
    public.fight_series_members,
    public.media_objects,
    public.fight_posts,
    public.fight_post_media,
    public.fight_post_tags,
    public.fight_post_reactions,
    public.fight_post_comments,
    public.fight_post_channels
    to service_role;

grant usage, select on all sequences in schema public to service_role;

-- Build 113 still names a profile, creates a Fight, invites, accepts, and reads Steps.
grant select on public.profiles to authenticated;
grant update (display_name, avatar_path, time_zone, handle, handle_set_at)
    on public.profiles to authenticated;

grant select, insert on public.friendships to authenticated;
grant update (state) on public.friendships to authenticated;

grant select on public.fights to authenticated;
grant insert (
    owner_id, name, state, starts_at, ends_at, time_zone, metric,
    outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text
) on public.fights to authenticated;

grant select on public.data_sources to authenticated;

grant select on public.fight_members to authenticated;
grant insert (fight_id, user_id, state, accepted_at) on public.fight_members to authenticated;
grant update (state, accepted_at) on public.fight_members to authenticated;

-- token_hash stays off the client.
grant select (id, fight_id, invited_user_id, expires_at, revoked_at, accepted_at)
    on public.fight_invites to authenticated;

grant select on public.step_days to authenticated;
grant select on public.metric_days to authenticated;
grant select on public.fight_series to authenticated;
grant select on public.fight_series_members to authenticated;

grant select on public.feedback_posts to authenticated;
grant select on public.feedback_comments to authenticated;
grant select on public.feedback_post_media to authenticated;
grant select on public.media_objects to authenticated;
grant select on public.fight_posts to authenticated;
grant select on public.fight_post_media to authenticated;
grant select on public.fight_post_tags to authenticated;
grant select on public.fight_post_reactions to authenticated;
grant select on public.fight_post_comments to authenticated;
grant select on public.fight_post_channels to authenticated;

-- Identity inserts from the server. The owner is postgres. service_role also has
-- insert on these tables, so it needs the sequence to omit the id.
grant usage, select on sequence
    private.fight_admin_actions_id_seq,
    private.profile_lookup_attempts_id_seq
    to postgres, service_role;

commit;
