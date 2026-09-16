-- Disposable CI only, applied immediately before the Profile expansion migration.
insert into auth.users(id) values
    ('71000000-0000-4000-8000-000000000001'),
    ('71000000-0000-4000-8000-000000000002');

insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy) values
    ('72000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000001', 'Historical final', 'live', now() - interval '20 days', now() - interval '10 days', 'UTC', 'highest_total', 'shared'),
    ('72000000-0000-4000-8000-000000000002', '71000000-0000-4000-8000-000000000001', 'Historical ongoing', 'live', now() - interval '1 day', now() + interval '1 day', 'UTC', 'highest_total', 'shared'),
    ('72000000-0000-4000-8000-000000000003', '71000000-0000-4000-8000-000000000001', 'Future invitations', 'inviting', now() + interval '2 days', now() + interval '3 days', 'UTC', 'highest_total', 'shared');

insert into public.fight_members(fight_id, user_id, state, accepted_at, current_value, rank, final_steps_complete)
select fight.id, person.id,
    case when fight.state = 'inviting' then 'invited'::public.fight_member_state else 'accepted'::public.fight_member_state end,
    case when fight.state <> 'inviting' then now() - interval '21 days' end,
    case when person.id = '71000000-0000-4000-8000-000000000001' then 3000 else 1000 end,
    case when person.id = '71000000-0000-4000-8000-000000000001' then 1 else 2 end,
    true
from public.fights fight cross join auth.users person
where fight.id in ('72000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000002', '72000000-0000-4000-8000-000000000003')
    and person.id in ('71000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000002');
-- Existing score protection strips scores on INSERT; the scoring writer uses UPDATE.
update public.fight_members set
    current_value = case when user_id = '71000000-0000-4000-8000-000000000001' then 3000 else 1000 end,
    rank = case when user_id = '71000000-0000-4000-8000-000000000001' then 1 else 2 end
where fight_id = '72000000-0000-4000-8000-000000000001';
update public.fights set state = 'final' where id = '72000000-0000-4000-8000-000000000001';
update public.fight_members set state = 'withdrawn'
    where fight_id = '72000000-0000-4000-8000-000000000002' and user_id = '71000000-0000-4000-8000-000000000002';
