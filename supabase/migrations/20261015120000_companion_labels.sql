begin;

set local lock_timeout = '5s';

-- A custom character's name and line show on its owner's companion card and profile, like a Special's caption.
-- The owner saves both together. lines_action_key is the idempotency key of the first suggestion batch, so the
-- app and the reconciler start that batch once.
alter table private.custom_character_purchases
    add column name text,
    add column line text,
    add column lines_action_key uuid,
    add constraint custom_character_name_limits
        check (char_length(name) between 1 and 24 and name = btrim(name) and name !~ ('[\n\r' || chr(8232) || chr(8233) || ']')),
    add constraint custom_character_line_limits
        check (char_length(line) between 1 and 60 and line = btrim(line) and line !~ ('[\n\r' || chr(8232) || chr(8233) || ']')),
    add constraint custom_character_label_pair check ((name is null) = (line is null));

-- Blend's full final response for a run that failed, was cancelled, or returned something unreadable.
alter table private.ai_requests add column provider_response jsonb;

-- Suggestion batches are free character work, like the portraits and poses.
alter table private.ai_requests drop constraint ai_paid_character_no_credits;
alter table private.ai_requests add constraint ai_paid_character_no_credits
    check (resource_id is null or (workflow in ('avatar', 'fitness', 'companion_lines') and credit_price = 0 and credit_state = 'none'));

commit;
