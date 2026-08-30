# FitFight Domain

FitFight turns a time-bounded fitness competition between people into a shared, auditable result. This glossary fixes the product language independently of any database, API, or client implementation.

## People

**User**:
A person with a FitFight identity.
_Avoid_: Account, athlete, customer

**Profile**:
The public-facing name, handle, photo, and preferences attached to a User.
_Avoid_: User record, account

**Friendship**:
A mutually accepted relationship that makes it easier for two Users to invite one another.
_Avoid_: Follow, contact

## Fights

**Fight**:
A time-bounded fitness competition with one shared window, Metric, rules, and Stakes. Invited Users may become Fight members after it begins and receive full-window credit from accessible history.
_Avoid_: Challenge, contest, event

**Fight member**:
A User's participation in one Fight, including invitation and acceptance state.
_Avoid_: Player record, role

**Fight owner**:
The Fight member who created the Fight. Ownership permits limited administration but never access to another member's private source data.
_Avoid_: Admin, banker

**Fight acceptance**:
A User's agreement to join a Fight under its existing rules and full Fight window, use the selected Data source, and share the resulting score and provenance with the other Fight members.
_Avoid_: Data grant, provider permission

**Invite**:
A revocable offer for a User or recipient to become a Fight member before or during the Fight; it expires when the Fight window closes.
_Avoid_: Share link, request

**Fight window**:
The exact interval during which qualifying activity contributes to a Fight.
_Avoid_: Date range, duration

**Fight day**:
A calendar day interpreted in the Fight's declared time zone.
_Avoid_: User day, local day

**Metric**:
The canonical quantity observed by FitFight, with a defined unit and meaning. Steps is the first production Metric; a Metric is not by itself a scoring method.
_Avoid_: Provider metric, health type

**Metric definition**:
The versioned meaning of a Metric, including its canonical unit and which observations are eligible. Two measurements that are not genuinely comparable require different Metric definitions even if a provider gives them similar names.
_Avoid_: Provider field, scoring rule

**Measure**:
The activity data selected by a Fight, such as Steps, distance, active minutes, or workouts, together with any rules needed to decide what counts.
_Avoid_: Score, Result rule

**Fight rule**:
A Fight's immutable combination of one Measure, one Score rule, and one Result rule.
_Avoid_: Settings, options

**Score rule**:
The calculation that turns a Fight member's Measure into their Score, such as total, average per day, or number of days reaching a value.
_Avoid_: Metric, Result rule

**Score**:
The number that shows a Fight member's progress: total Steps, successful days, average Steps per day, qualified workouts, or another explicitly labelled unit.
_Avoid_: Observation, raw total, result

**Target**:
An accepted goal used by a Score rule or Result rule, such as 10,000 Steps per day or five successful days.
_Avoid_: Unscoped goal, Score

**Goal policy**:
The Fight rule that decides whether a Target is shared by every member or chosen personally by each member.
_Avoid_: Difficulty, goal type

**Personal target**:
A Target value chosen by one Fight member before their membership terms lock.
_Avoid_: Role, handicap, private goal

**Goal recommendation**:
A private, history-based target suggestion that a User may accept, adjust, or ignore before their membership terms lock.
_Avoid_: Medical advice, required target

**Stake**:
The agreed consequence of a Fight, such as bragging rights, money, or an action. A Stake is not money held by FitFight.
_Avoid_: Balance, wallet, payment

**Result rule**:
The part of a Fight rule that decides what a Score means: highest wins, reaching a value succeeds, or the outcome is proportional.
_Avoid_: Outcome rule, settlement mode, payout type

**Score projection**:
The current, reversible view of a Fight member's score and likely outcome before finalization.
_Avoid_: Result, live result

**Final result**:
The immutable outcome produced after the Fight window and final synchronization grace period close.
_Avoid_: Projection, current result

## Activity data

**Activity**:
A source-attributed exercise session such as running, swimming, or volleyball. An Activity may carry several Metrics but is not itself a Metric.
_Avoid_: Metric, sport table, raw workout

**Data provider**:
A system from which fitness observations originate, such as Apple Health, WHOOP, Strava, or Health Connect.
_Avoid_: Device, integration, app

**Data source**:
The specific origin selected for a Metric, including the provider and originating device or app when known. Its identity remains visible with the resulting score or shared activity.
_Avoid_: Provider connection

**Provider connection**:
A link between a User and a Data provider that lets FitFight synchronize supported activity until disconnected.
_Avoid_: Fight acceptance, Data source

**Collection consent**:
A User's permission for FitFight to import accessible supported history and continuously process new activity from a Provider connection until revoked.
_Avoid_: Fight acceptance, provider scope

**Observation**:
A time-stamped canonical fitness fact eligible to contribute to a Metric.
_Avoid_: Score, provider payload, sample

**Provenance**:
The origin and transformation history that explains how an Observation was produced.
_Avoid_: Metadata, source name

**Sync checkpoint**:
The latest provider position and event time FitFight has successfully processed for a User's Data source.
_Avoid_: Last refresh, cursor

**Data freshness**:
The age and completeness of the observations behind a displayed Score projection.
_Avoid_: Online status, sync status
