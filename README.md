# FitFight

Challenge your friends. Winner takes the glory.

Cloud-only iOS app: Marc talks from his phone, a Cursor cloud agent codes, GitHub Actions (`macos-26`) ships to TestFlight. No home Mac.

**v0 is on TestFlight** (`0.1.0`): name on screen, version at the top, Versions list.

## Agents

Read [`AGENTS.md`](AGENTS.md) and [`docs/`](docs/README.md) before changing anything. That’s the project memory for parallel chats.

## Marc

Talk to the agent. Test ~30 min/day. Evening: TestFlight → Update. Same-day build: Actions → **TestFlight** → Run workflow.

Do not paste the `.p8` into chat. Setup (Apple app, API key, GitHub secrets) is already done — see `docs/shipping.md`.
