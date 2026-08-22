# FitFight

Challenge your friends. Winner takes the glory.

Cloud-only iOS app: you talk, a Cursor cloud agent codes, GitHub Actions (macOS) ships to TestFlight once a day. No home Mac. No Xcode on your desk.

v0 is a one-screen app whose job is to prove the loop: it builds, it shows `0.1.0 (build)` at the top of the screen, it lands on your phone.

## Once (only you can do this)

1. **App Store Connect** → Apps → New App. iOS, name **FitFight**, bundle ID **`com.fitfight.mvp`**.
2. **Users and Access** → **Integrations** → **App Store Connect API** → Generate an **Admin** (or App Manager) key. Download the `.p8` once. Copy **Key ID** and **Issuer ID**.
3. **Team ID**: Apple Developer → Membership → Team ID (10 characters).
4. In this GitHub repo: **Settings → Secrets and variables → Actions**. Add:

   | Secret | What to paste |
   | --- | --- |
   | `APP_STORE_CONNECT_KEY_ID` | Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
   | `APP_STORE_CONNECT_API_KEY` | Full `.p8` file contents |
   | `APPLE_TEAM_ID` | Team ID |

5. **TestFlight** on your iPhone. In App Store Connect, add yourself as an **Internal** tester (fast). Friends can wait — first **external** build needs Apple’s beta review (~1–2 days, once).
6. Merge the pipeline PR if it isn’t on `main` yet. Then tell the agent “secrets are in” (or run **Actions → TestFlight → Run workflow**).

Do **not** paste the `.p8` into chat.

## After that

Talk to the cloud agent. Test ~30 min/day. Evening build: TestFlight → Update. Version is at the **top of the screen**, e.g. `0.1.0 (42)`.

Optional same-day fix: ask the agent to run the TestFlight workflow, or run it yourself from the Actions tab.

## CI

- **Simulator compile** on every PR (`macos-26`, GitHub-hosted).
- **TestFlight** daily at 18:00 UTC + manual `workflow_dispatch`.
- Repo is **public**, so GitHub-hosted macOS minutes are free. Keep it public if you want $0 CI. Signing keys live in Actions secrets, not in git.

Do not add a self-hosted runner or a home Mac.
