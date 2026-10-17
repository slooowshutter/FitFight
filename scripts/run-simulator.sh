#!/bin/bash
# Runs the real app (not the Companion preview) in this workspace's own Simulator against a backend.
#   scripts/run-simulator.sh                  this workspace's `npm run dev` (web/, port 3000), staging database
#   scripts/run-simulator.sh staging          staging.fitfight.app, staging database
#   scripts/run-simulator.sh local-db         this workspace's own Supabase in Docker, own server, fake accounts
#   scripts/run-simulator.sh local-db reset   the same, after wiping that database and replaying every migration
#   scripts/run-simulator.sh local-db stop    stops that database (its data stays) and its server
# local-db applies this branch's migrations, new ones included, so a schema change is tested before it reaches
# staging. It signs in as @alex.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p .context

# One Supabase stack per workspace: its own Docker project and ports from Conductor's per-workspace block.
workspace="$(basename "$PWD")"
base="${CONDUCTOR_PORT:-$((40000 + $(printf %s "$workspace" | cksum | cut -d' ' -f1) % 900 * 10))}"
server_port=$((base + 5))
export SUPABASE_PROJECT_ID="fitfight-$workspace" SUPABASE_API_PORT=$((base + 6)) \
    SUPABASE_DB_PORT=$((base + 7)) SUPABASE_DB_SHADOW_PORT=$((base + 8))
supabase() { npm exec --yes --package=supabase@2.115.0 --package=@supabase/cli-darwin-arm64@2.115.0 -- supabase "$@"; }
if [[ "${1:-}" == local-db && "${2:-}" == stop ]]; then
    supabase stop > /dev/null 2>&1
    lsof -tiTCP:"$server_port" -sTCP:LISTEN | xargs kill 2> /dev/null || true
    exit 0
fi

# One Simulator per workspace: other workspaces install their own builds, so a shared one runs someone else's app.
simulator_id="$(xcrun simctl list devices available | grep -F "FitFight $workspace (" | grep -oE '[0-9A-F-]{36}' || true)"
[[ -n "$simulator_id" ]] || simulator_id="$(xcrun simctl create "FitFight $workspace" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-26-5)"
xcrun simctl boot "$simulator_id" 2> /dev/null || true
xcrun simctl bootstatus "$simulator_id" -b > /dev/null
sim_env() { xcrun simctl spawn "$simulator_id" launchctl "$@"; }

# launchctl keeps these for every launch until the Simulator reboots, including taps on the icon.
for name in FFAPIBaseURL FFSupabaseURL FFSupabasePublishableKey FF_DEV_ACCESS_TOKEN FF_DEV_REFRESH_TOKEN; do
    sim_env unsetenv "$name"
done

case "${1:-local}" in
    local) sim_env setenv FFAPIBaseURL "http://127.0.0.1:${PORT:-3000}" ;;
    staging) ;;
    local-db)
        supabase start -x studio,postgres-meta,mailpit,logflare,vector,imgproxy,edge-runtime,supavisor \
            > .context/supabase-start.log 2>&1 || { tail -20 .context/supabase-start.log; exit 1; }
        if [[ "${2:-}" == reset ]]; then
            step="db reset"
            # The reset deletes every session, so the app's saved one would be rejected.
            xcrun simctl keychain "$simulator_id" reset
        else
            step="migration up"
        fi
        supabase $step --local >> .context/supabase-start.log 2>&1 || { tail -20 .context/supabase-start.log; exit 1; }
        eval "$(supabase status -o env 2> /dev/null)"

        auth=(-H "apikey: $SECRET_KEY" -H "Authorization: Bearer $SECRET_KEY" -H "Content-Type: application/json")
        # The same people as the Companion preview. An existing account answers 422.
        for person in 1:Alex 2:Leo 3:Nina 4:Sam; do
            name="${person#*:}"
            code="$(curl -sS "${auth[@]}" "$API_URL/auth/v1/admin/users" -o /dev/null -w '%{http_code}' -d "{
                \"id\": \"c0000000-0000-4000-8000-00000000000${person%%:*}\",
                \"email\": \"$(tr '[:upper:]' '[:lower:]' <<< "$name")@fitfight.local\",
                \"password\": \"local-dev-only\", \"email_confirm\": true,
                \"user_metadata\": { \"full_name\": \"$name\" }
            }")"
            [[ "$code" == 200 || "$code" == 422 ]] || { echo "Creating $name failed: HTTP $code" >&2; exit 1; }
        done
        # Usernames and companions are set directly so the app skips onboarding.
        docker exec -i "supabase_db_$SUPABASE_PROJECT_ID" psql -q -v ON_ERROR_STOP=1 -U postgres << 'SQL'
update public.profiles p set handle = v.handle, handle_set_at = now(), companion_id = v.companion
from (values (1, 'alex', 'fox'), (2, 'leo', 'bear'), (3, 'nina', 'otter'), (4, 'sam', 'badger')) as v (n, handle, companion)
where p.user_id = ('c0000000-0000-4000-8000-00000000000' || v.n)::uuid and p.handle_set_at is null;
SQL

        server="http://127.0.0.1:$server_port"
        if ! lsof -iTCP:"$server_port" -sTCP:LISTEN > /dev/null; then
            # Variables already in the environment win over web/.env.local. Besides the database, this blanks the
            # services that reach real people (Notion backlog, Cursor agents, push). Blend stays on for AI work.
            NEXT_PUBLIC_SUPABASE_URL="$API_URL" SUPABASE_SECRET_KEY="$SECRET_KEY" DATABASE_URL="$DB_URL" \
                NOTION_TOKEN= CURSOR_API_KEY= APNS_PRIVATE_KEY= OPENROUTER_API_KEY= \
                nohup npm --prefix web run dev -- --port "$server_port" > .context/web-local-db.log 2>&1 < /dev/null &
        fi
        for _ in $(seq 60); do curl -s -o /dev/null "$server/api/v1/environment" && break; sleep 1; done
        curl -s -o /dev/null "$server/api/v1/environment" || { tail -20 .context/web-local-db.log; exit 1; }

        session="$(API_URL="$API_URL" KEY="$PUBLISHABLE_KEY" SERVER="$server" python3 scripts/local-db-seed.py)"
        read -r access refresh <<< "$session"
        sim_env setenv FFAPIBaseURL "$server"
        sim_env setenv FFSupabaseURL "$API_URL"
        sim_env setenv FFSupabasePublishableKey "$PUBLISHABLE_KEY"
        sim_env setenv FF_DEV_ACCESS_TOKEN "$access"
        sim_env setenv FF_DEV_REFRESH_TOKEN "$refresh"
        echo "Database $DB_URL, server $server (log .context/web-local-db.log)"
        ;;
    *) echo "usage: $0 [local|staging|local-db [reset|stop]]" >&2; exit 1 ;;
esac

# Builds stay out of .context: Conductor keeps .context forever after archiving a workspace.
derived="$HOME/Library/Developer/Xcode/DerivedData/FitFight-$workspace"
# Ad-hoc signing embeds the simulator entitlements; without them sign-in cannot save to the Keychain.
xcodebuild -project FitFight.xcodeproj -scheme FitFight -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
    build > .context/simulator-build.log 2>&1 || { tail -30 .context/simulator-build.log; exit 1; }

xcrun simctl install "$simulator_id" "$derived"/Build/Products/Debug-iphonesimulator/FitFight.app
xcrun simctl launch --terminate-running-process "$simulator_id" com.fitfight.mvp
open -a Simulator --args -CurrentDeviceUDID "$simulator_id"
