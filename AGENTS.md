# FitFight — for agents

Read this first, then `docs/`. Marc talks from his phone, often transcribing. Be concise. Do the work in the cloud. Do not send him into Apple/GitHub docs.

**Owner:** Marc Lamy (`marc@marclamy.com`)  
**Repo:** https://github.com/marclelamy/FitFight (public)  
**Loop:** Marc (phone) → Cursor **cloud** agent → PR into `develop` → you try it → merge `develop` into `main` when it should be production → GitHub Actions `macos-26` → TestFlight → iPhone.

## Hard rules

- Cloud only. No home Mac, no Hermes, no self-hosted runner, no Xcode on Marc’s desk.
- This Linux environment cannot compile or upload iOS. CI on GitHub-hosted `macos-26` does that.
- Never put `.p8` / API keys / provisioning profiles in git or chat.
- Keep the repo **public** (free GitHub macOS minutes). Don’t make it private without saying so.
- Version label stays at the **top of the screen** (not the nav bar), e.g. `0.9.0 (48) · staging · 25 Aug`.
- Permanent **Versions** button: under You → Settings, and the version label at the top. Every user-facing ship adds a `ReleaseNote` in `FitFight/Changelog.swift` (same marketing version, new date/notes) and updates **Last TestFlight** in `docs/backlog.md`.
- **Do not bump `MARKETING_VERSION` for TestFlight.** Phones already have **0.9.0** from the live-fight builds. Stay on `0.9.0`. Do not drop back to `0.8.0` — TestFlight will not replace `0.9.0 (42)` with `0.8.0 (47)`. CI still increments the **build number**. Changelog rows reuse `0.9.0`. Only bump marketing version for an App Store ship or if Marc asks.
- Design tokens live in `docs/design/source/tokens.json` and are copied byte-for-byte into `FitFight/DesignSystem/tokens.json` for the app bundle. Don’t hardcode colours. The current system is **Night/Day with fixed semantic families**: Moss is you/winning, Ember is urgency/losing, and Gold is progress only. There is no accent picker.
- Talk to Marc only for things only he can do: Apple login, GitHub secrets, TestFlight testers, legal, the hosted Supabase dashboard. Agents cannot `workflow_dispatch`. App pushes (PR branch, `develop`, or `main`) upload to TestFlight by themselves. Tell Marc a build is coming; he opens TestFlight → Update. Do not ask him to Run workflow.
- Never nuke the hosted database. No `supabase db reset` / `db push` against production or `develop`, no `DROP TABLE` / `TRUNCATE` / `DROP SCHEMA` / `DROP DATABASE` unless Marc asked in that chat and the migration starts with `-- allow-destructive`. Never put `sb_secret_...`, `service_role`, or the database password in git, chat, or iOS. Never merge to `main` unless Marc asked to ship to production. Never merge to `develop` unless Marc asked. Production migrations apply only after `develop` is merged to `main`.

## What exists (2026-08-25)

Current map: [`docs/status.md`](docs/status.md). Sign-in, username, create/accept Steps fight, HealthKit upload, and standings work on staging after #30 is merged. No Vercel required for that path.

- Native SwiftUI iOS app, scheme `FitFight`, bundle ID `com.fitfight.mvp`.
- First TestFlight upload **succeeded** (build `0.1.0 (1)`). Latest user-facing ship: **0.9.0** welcome + develop Supabase.
- TestFlight on every app push (PR branch or `main`), plus daily **18:00 UTC**.
- Simulator compile on every PR.
- Approved design dump in `docs/design/source/` (338 tokens, 76 screenshots). Dark/light + 10 accents.
- Four tabs: Fights, New, Requests, You. The Design experiment tab is gone.

**What works vs fake vs next:** [`docs/status.md`](docs/status.md). Read that before building.

Details: [docs/status.md](docs/status.md) · [docs/product.md](docs/product.md) · [docs/backlog.md](docs/backlog.md) · [docs/system-design.md](docs/system-design.md) · [docs/backend.md](docs/backend.md) · [docs/shipping.md](docs/shipping.md) · [docs/history.md](docs/history.md) · [docs/design/source/README.md](docs/design/source/README.md)

[`docs/system-design.md`](docs/system-design.md) is the golden guide for production. Follow it so new work fits. Do **not** implement that document. Do **not** build Active Minutes, Workout Count, WHOOP, Strava, payments, notifications, social, or the website until the backlog says so.

Right now: empty platform in `supabase/` (see [`docs/backend.md`](docs/backend.md)), then the minimum Steps Fight. The mock UI may still show three metrics because that is the design kit. Production scoring is Steps only.

Product ideas go in [`docs/backlog.md`](docs/backlog.md). Marc says “put X on the backlog”; do not open GitHub Issues or a Notion board unless he asks.

## When you change the native iOS app

1. Branch off `develop`. Open a PR **into `develop`**. Do not PR into `main` unless Marc is shipping to production.
2. Add new `.swift` files to `FitFight.xcodeproj/project.pbxproj` (explicit file list, not a synchronized group). JSON in `DesignSystem/` must also be in the Resources build phase.
3. If users will see it: append a `ReleaseNote` in `Changelog.swift` using the current `MARKETING_VERSION` (`0.9.0`). Do **not** change `MARKETING_VERSION` in `project.pbxproj`. CI bumps the build number. Only bump marketing version when Marc is shipping to the App Store or he asked in that chat.
4. Don’t ask Marc to open Xcode or his Mac. After you push app code, TestFlight uploads itself. He opens TestFlight → Update. Do not ask him to merge first, or to Run workflow.
5. Shipping to production is Marc merging `develop` → `main`. Agents do not do that unless he said so in that chat.
6. Merged feature branches are deleted by CI. `main` and `develop` stay. Do not enable GitHub’s “Automatically delete head branches.”

## Coding conduct — all languages

These rules apply to Swift, TypeScript, SQL, scripts, and documentation. The detailed TypeScript rules in the next section do **not** apply to Swift or SwiftUI.

- Do exactly the requested task. Do not add features, options, abstractions, fallbacks, retries, refactors, or cleanup that the request does not require.
- Keep the diff surgical. Every changed line must trace to the request. Match the style of the file being changed.
- Remove imports, variables, functions, and files that **your change** makes unused. Do not remove pre-existing dead code unless asked.
- State material assumptions. Ask before coding only when different answers would produce meaningfully different work and the answer cannot be found in the repo.
- For multi-step work, define verifiable success criteria, implement to those criteria, and run the smallest relevant checks.
- When blocked by missing credentials, information, or a product decision, stop and ask. Do not fake, stub, or guess past the gap.
- Report what was completed and verified, what was skipped and why, and what is still needed.

## TypeScript and Next.js — `web/` only, never Swift

Everything in this section applies only to JavaScript, TypeScript, and TSX under `web/`. It does **not** apply to `.swift` files, SwiftUI views, native models, HealthKit code, or Xcode project structure. Do not translate these rules into Swift conventions. Zod is a TypeScript runtime validator; it is not a requirement for native code.

The product scope rules above still win. The existence of this section does not authorize building the website or any deferred backend feature. Use these standards only when the task already calls for work under `web/`.

### Tooling and framework

- Run web commands from `web/`.
- Use `npm`, not `pnpm` or `yarn`; `web/package-lock.json` and CI use npm.
- Keep TypeScript strict. Do not weaken `web/tsconfig.json`, add `any`, or use assertions merely to silence a type error.
- `web/package.json` is the source of truth for the installed Next.js, React, TypeScript, and Zod versions. APIs and conventions may differ from training data.
- Before using an unfamiliar Next.js API, read the matching installed guide in `web/node_modules/next/dist/docs/` when dependencies are present. If it is absent, check documentation for the version declared in `web/package.json`; do not install dependencies only to read docs.
- This project uses the App Router and Route Handlers. Follow `docs/system-design.md`; server routes use the Node.js runtime, not Edge, unless the architecture changes explicitly.
- After TypeScript changes, normally run `npm run typecheck` and the relevant tests from `web/`. Run the full `npm test` when the change can affect shared backend behavior.

### Code shape — fewest functions that do the job

Write few, deep functions. One function that reads from top to bottom is often better than many small functions that make the reader jump between them. Do not split a job into pieces only to make each piece look tidy.

Do not extract a function when:

- It has one call site and does not name a meaningful domain concept.
- Its body is one return, object literal, ternary, template string, comparison, `find`, or `map`.
- It only renames, reshapes, unwraps, or forwards a value already held by the caller.
- It exists only to make the calling function look shorter.
- It is speculative and no second caller exists.

Names such as `get*`, `is*`, `has*`, `resolve*`, `normalize*`, `describe*`, `format*`, `build*`, `make*`, `to*`, `compute*`, `with*`, `ensure*`, `prepare*`, `derive*`, and `extract*` often reveal unnecessary single-use helpers. Use one when it has at least two real call sites, hides substantial complexity, or gives a real domain operation a name.

- A normal feature should add roughly 1–3 functions. If a plan needs more than five, simplify before coding.
- Inline single-use short logic as a loop, callback, or local expression.
- Extract when logic has two or more callers, is substantial pure logic worth testing, hides a complex boundary, or names a domain operation readers need.
- Keep a helper file-private until a second module needs it.
- Do not add a new file for a one-line utility.
- Before finishing, count the functions added and inline short single-use helpers.

```ts
// WRONG — three single-use helpers make one flow harder to read
function normalizeFightID(id: string) { return id.trim().toLowerCase(); }
function isFinalFight(fight: Fight) { return fight.state === "final"; }
function getFightLabel(fight: Fight) { return `${fight.name} (${fight.state})`; }
export function summarizeFight(id: string, fights: Fight[]) {
  const fight = fights.find((item) => item.id === normalizeFightID(id));
  if (!fight) return null;
  return { label: getFightLabel(fight), final: isFinalFight(fight) };
}

// RIGHT — one function keeps the operation visible
export function summarizeFight(id: string, fights: Fight[]) {
  const fight = fights.find((item) => item.id === id.trim().toLowerCase());
  if (!fight) return null;
  return { label: `${fight.name} (${fight.state})`, final: fight.state === "final" };
}
```

### Defensive code — validate boundaries, trust types internally

Validate untrusted data at trust boundaries: HTTP bodies, path and query parameters, database rows without generated types, provider and third-party responses, `process.env`, files, webhooks, local storage, and values typed `unknown` or `any`. Parse once, then use the parsed value internally without repeating the same checks.

Do not add:

- `??` or `||` fallbacks for values whose types say they are present.
- Null checks on parameters typed as non-nullable.
- `typeof`, `Array.isArray`, or property-existence checks on already validated typed values.
- Optional chaining on required fields.
- `try`/`catch` around ordinary internal calls.
- A catch that logs an error and continues with a default value.
- A retry, fallback, or default for a failure that has not been observed or specified.

Business validation is not excessive defensive code. Authentication, authorization, Fight state transitions, scoring invariants, idempotency, and source compatibility are real domain rules. Keep them.

Use the established `apiRoute`, `readJson`, `ApiError`, and `errorResponse` boundary in `web/src/server/http.ts` where it fits. Let unexpected internal failures reach that boundary. Catch locally only when the code can recover meaningfully or must translate a known external failure into a stable domain/API error.

### Types and Zod schemas

Default to Zod when a value is persisted or parsed from a runtime boundary. Use plain `type` or `interface` only for compile-time-only structures such as internal UI state, algorithm inputs after validation, and calculated results that never cross a boundary.

#### Placement

- Every new named type, interface, literal-value set, and Zod schema lives in `web/src/lib/types/<domain>/` and is imported through `@/lib/types/...`.
- This includes API request and response contracts, database boundary schemas, provider payloads, webhooks, environment/config objects, forms, and persisted data.
- Existing files may predate this rule. Do not copy their placement for new declarations. Move an old declaration only when the requested change materially edits or reuses it; do not perform a repo-wide migration as drive-by cleanup.
- A component's own props may stay inline in the component signature. Do not create a standalone `FooProps` or `FooParams` for props used once.
- Small callback parameter types should be inferred. Do not create named types solely to annotate one local callback.
- Generated Supabase database types are generated artifacts. Never hand-edit them.

#### Naming

```ts
export const fightStateValues = ["draft", "live", "final"] as const;
export const fightStateSchema = z.enum(fightStateValues);

export const fightSummarySchema = z.object({
  id: z.string().uuid(),
  state: fightStateSchema,
});

export type FightState = z.infer<typeof fightStateSchema>;
export type FightSummary = z.infer<typeof fightSummarySchema>;
```

- Schemas use `camelCase` plus the `Schema` suffix: `fightSummarySchema`.
- Inferred types use `PascalCase` with no suffix: `FightSummary`, never `FightSummarySchema`.
- Runtime literal sets use a descriptive `Values` suffix and `as const`; derive both the Zod enum and TypeScript union from that one source.
- Do not add TypeScript `enum` or `export enum`. Use a const value array plus `z.enum`.
- Form schemas use `xxxFormValuesSchema`; the inferred type is `XxxFormValues`.

#### Schema rules

1. Export both the schema and its inferred type when data crosses a parse boundary.
2. Define schemas before inferred types. In files with three or more schemas, keep related schemas together and group their `z.infer` exports below them.
3. Derive types from schemas. Do not manually duplicate a Zod shape as a separate interface.
4. Prefer `Omit<z.infer<typeof baseSchema>, "field"> & { field: StrongerType }` over copying a whole shape when an internal type strengthens one field.
5. Use `z.input<typeof schema>` only for the value before coercion or transformation. Use `z.infer<typeof schema>` or `z.output<typeof schema>` after parsing.
6. Use `safeParse` when the caller must branch on validation and return a specific response. Use `parse` only when the established API boundary should convert the resulting `ZodError`.
7. Do not parse data again after a trusted framework, generated client, or earlier boundary has already validated the same value against the same contract.
8. Do not use `as SomeType` as a substitute for parsing untrusted data.

Canonical route-boundary shape:

```ts
const body = await readJson(request);
const parsed = createFightRequestSchema.safeParse(body);

if (!parsed.success) {
  throw parsed.error;
}

const input = parsed.data;
// input is trusted from here; do not repeat shape or typeof checks
```

### TypeScript comments

Default to zero comments. A comment must add information that names and types cannot express.

- Explain why, a domain invariant, a framework footgun, an ordering dependency, or a non-obvious tradeoff. Never narrate obvious code.
- Keep a comment on the exact code it explains. Do not stack multiple comments that say the same thing or leave comments that drift from the implementation.
- Add JSDoc to exported functions and types only when it adds a contract, invariant, unit, trust boundary, or behavior not already clear from the signature.
- Do not add `@param` or `@returns` when TypeScript already expresses the information.
- Use numbered step comments only for routes, runners, and handlers with at least three distinct phases.
- Use large `═══ SECTION ═══` dividers only in files of roughly 300+ lines that mix distinct concerns.
- Use `// NOTE:` immediately before a real footgun. Use uppercase `// TODO:` on its own line for unfinished work.
- When editing code, correct or delete comments made false by the change. Do not add comments merely because nearby code has none.

### TypeScript completion check

Before finishing work under `web/`:

1. Re-read the request and remove unrequested code.
2. Check that runtime inputs are validated once at their boundary and trusted afterward.
3. Check that new shared declarations and Zod schemas are in `web/src/lib/types/<domain>/` with schema-derived types.
4. Check that short single-use helpers were not added without a real reason.
5. Run the relevant typecheck and tests, then report exactly what passed or why a check could not run.
