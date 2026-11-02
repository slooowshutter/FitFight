# FitFight AI workflows

Since 20 Oct 2026 FitFight runs its own AI workflows; Blend only finishes runs started
before. Marc asked for this because Blend added about 40 s to every run. The app contract
(`/api/v1/ai/runs`), sign-in, credits, paid and free characters, reconciliation and the
request records in [Blend workflows](blend-workflows.md) are unchanged. Only the part that
runs the models moved.

## Where the code is

| File | What it holds |
| --- | --- |
| `web/lib/ai/workflows.ts` | Every workflow, one function each, using the shared text, JSON and image helpers |
| `web/lib/ai/prompts.ts` | Every prompt, copied word for word from the versions Blend published (what players got), and the links to the two style pictures |
| `web/lib/ai/steps.ts` | The helpers: `text` and `json` (OpenRouter) and `image` (Azure first, then OpenRouter). Model calls log one row per attempt. Drawing and upload are separate durable steps |
| `web/lib/ai/runner.ts` | `startAiWorkflow` and `readAiWorkflowRun`: start a run, read its state. A non-`fitfight:` id goes to Blend |
| `web/lib/supabase/queries/ai-steps-supabase-query.ts` | The step log insert and the picture upload |
| `supabase/migrations/20261020120000_ai_steps.sql` | `private.ai_steps`, the `ai-images` bucket, picture link checks |

| Workflow | Steps | Was Blend |
| --- | --- | --- |
| `avatar` | GLM 5.3 Flash cleans the words, then Sunburst draws (1024x1024, style picture) | `c405d12d` |
| `fitness` | Gemini 2.5 Flash lists the portrait's signature items, then 5 Sunburst drawings at once | `fa770c5b` |
| `groupPhoto` | GLM Flash keeps the scene in scope, then Sunburst draws (1536x1024) | `f740d71e` |
| `companionLines` | Claude Opus 5.5 (low reasoning) writes four names and lines as JSON | `8df8fe50` |
| `promptCheck` | Claude Haiku 5.5 writes a note and three rewrites as JSON | `6d906477` |
| `trail` | GLM Flash, Sunburst, then Claude Fable 5.1 counts the runners | `6a08d9c0` |
| `raceStart` | Sunburst, then Claude Fable 5.1 counts the featured runners | `963f78bf` |

The port keeps what Blend really sent, read from its code on 20 Oct 2026: Blend drew
characters square (it ignored the nodes' "2K, 2:3" fields), sent temperature 0.1 for
"focus" creativity and none otherwise, sent no reasoning setting for "none", and put the
connected pictures before the node's style pictures. FitFight leaves out Blend's generic
chat guidance and the group photo's unused count check.

## How a run works

1. The app's request passes sign-in, the input check and the paid, free or credit
   reservation, as before.
2. `startAiWorkflow` starts the workflow with the Vercel Workflow SDK. The request saves
   the run as `{ workflowId: "fitfight:<name>", versionId: <commit>, runId }`.
3. The SDK runs the steps in the background. It saves each finished step, so a crash or
   deploy continues from the first unfinished step and never pays twice for a finished
   call. Text steps retry up to 3 times; a drawing retries once. A 4xx answer (a refusal or a
   bad request) fails at once, except 408 and 429, which retry.
4. The drawing step records the charge and returns its image bytes. The SDK saves those bytes before the separate upload step starts.
   The upload step writes the public `ai-images` object at `<run>/<drawing-step>.png`. Upload retries reuse the same bytes and path.
   A storage failure cannot repeat the paid model call. The logged output URL names the destination, which becomes available after upload succeeds.
5. The app's polls and the reconcile cron read the run with `readAiWorkflowRun`. A completed
   run's return value is the result itself, checked against the workflow's result schema,
   then settled as before. Fight images read `{ image_url, check }`.

Status checks wait 3 s (5 s for names and lines). Live runs of all seven on 20 and 21 Oct
2026, from tap to answer: prompt check 4.3 s (Blend: 44 s median), names and lines 17 s
(Blend: 54 s), portrait 42 s (Blend: 130 s), fitness set 42 s (Blend: 134 s), group photo 47 s,
trail image 53 s (its check passed), race start 61 s (its check found two of 12 featured
runners missing, so the cron would draw again, as with Blend).

Blend's Animal Avatars draft has an unpublished 13 Oct change to the description cleaner: it
turns a theme ("70s hippie") into 2 or 3 accessories. FitFight copies the published version;
the draft is still in Blend (source workflow `9dee7a54`) if Marc wants that change.

## Logging

`private.ai_steps` keeps one row per model call attempt, with no retention limit: run, workflow, step,
attempt, provider, model, the version that answered, who ran it (the Azure region or the
company behind OpenRouter), status, error, start, duration, first token (text), input,
output, reasoning and cached tokens, the cost, the resolved prompt and picture links, the
answer, and the commit. The cost is what OpenRouter charged, or for an Azure drawing, OpenAI's
list price for its tokens ($5, $8 and $30 per million text input, picture input and output
tokens), because Azure credits pay for it. The admin dashboard's **AI** section reads it on
the iPhone and the web: money paid, Azure credits used, the share of drawings on Azure,
requests, success rate, median portrait and fitness times, wait before the first call, cost
per character, four charts, and tables by model, step, person and every model call.
App-run logs carry the reserved request ID before the workflow starts. They are removed through
that request when its owner deletes their account. The foreign key rejects later logs from a
workflow that finishes after deletion. Shared fight-image logs have no app request.
Fight-image timings require a saved `ready` image for the same run ID. Rejected, unreadable,
unjudged and partial runs remain in run counts but do not lower completed-run times.

## Azure drawings and the load balancer

Sunburst drawings run on Blend's five Azure regions, paid with Azure credits, like on Blend:
the same resources, keys and per-minute limits (`azureImageRegions` in
`web/lib/types/ai/step.ts`).

| Region | Drawings a minute | Secret |
| --- | --- | --- |
| Sweden Central | 3 | `AZURE_IMAGE_SWEDENCENTRAL_API_KEY` |
| Poland Central | 3 | `AZURE_IMAGE_POLANDCENTRAL_API_KEY` |
| East US 2 | 2 | `AZURE_IMAGE_EASTUS2_API_KEY` |
| West US 3 | 2 | `AZURE_IMAGE_WESTUS3_API_KEY` |
| UAE North | 2 | `AZURE_IMAGE_UAENORTH_API_KEY` |

For each drawing, the `image` step picks a random region that has started fewer drawings than
its limit in the last 60 seconds (`private.ai_image_slots`, one row per start, kept forever,
one lock so two steps never take the same last slot). If Azure answers busy, missing or a
server error (404, 408, 429, 5xx) or the network fails, the drawing goes to the next free
region. When every region is full or has failed, OpenRouter draws it and charges money. A
refusal (another 4xx) stops the drawing. A region without its secret is skipped. Each try
writes its own row.

Blend's own load balancer counts its drawings in Upstash and cannot see FitFight's, so the two
can together go over a region's limit. Azure then answers 429 and the drawing moves on, as above.

Tested on 21 Oct 2026: 13 drawings at once filled Sweden Central 3, Poland Central 3, East
US 2 2, West US 3 2 and UAE North 2, and the 13th went to OpenRouter. A drawing on Azure took
36 to 55 s.

**Cost of a character:** 3 portraits plus 5 poses are 8 drawings at about $0.069 of Azure
credits each, $0.55, plus about $0.02 of text on OpenRouter (cleaning, signature items, names
and lines, prompt check). About $0.57 a character, of which about $0.02 is money while Azure
has room.

## Add a workflow

1. Add its prompts to `prompts.ts` and a function to `workflows.ts` that starts with
   `"use workflow"` and calls `text`, `json` or `image`.
2. Add its name and input schema in `web/lib/types/ai/step.ts` and a `case` in
   `startAiWorkflow`.
3. Write the caller (an app route or a cron), which reserves payment first.

## Configuration

`blendConfiguration.workflows[name].runner` in `web/lib/types/ai/workflow.ts` is
`"fitfight"` for every app workflow. Set one back to `"blend"` to start that workflow on
Blend again; its Blend id is kept beside it. Fight images use `fitfight:trail` and
`fitfight:race_start` in `fightImageConfiguration`.

`AI_WORKFLOWS_OPENROUTER_API_KEY` carries every text and vision call, and the drawings Azure
cannot take. It is its own name on purpose: `OPENROUTER_API_KEY` also turns on the daily
statuses, which production keeps off until a consent and disclosure review
([privacy compliance](app-store/privacy-compliance.md)). Without the key, a start answers
`ai_unavailable` and nothing is paid.

Warning: Do not add `OPENROUTER_API_KEY` to production for this. It turns the daily statuses
back on.

The two style pictures are still
links to Blend's storage (`AVATAR_STYLE_REFERENCE`, `FITNESS_STAGE_SHEET`); if Blend deletes
them, portraits and fitness sets fail until the links change.

## Local test

`supabase start` (local), then `next dev` with the local `DATABASE_URL`,
`NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_SECRET_KEY`, and the real OpenRouter key. The
Workflow SDK runs locally on its own. A local drawing's link is a `127.0.0.1` link, which
the picture checks refuse, so a local avatar ends `ai_invalid_result` after the full run;
the steps, costs and picture are all saved.
