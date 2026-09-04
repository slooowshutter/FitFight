# English and French localization for FitFight

Research date: **4 September 2026**

Repository baseline: **`1fd3eef`**, identical to `origin/develop` when reviewed

Source standard: current Apple documentation and Apple developer videos only.

## Recommendation

Localize the native app with an English-source `Localizable.xcstrings` catalog and a generic French (`fr`) localization. Add a separate `InfoPlist.xcstrings` catalog for the Apple Health purpose strings. Let iOS select the language from the person's system or per-app language preference; do not build a custom language preference or replace Apple's bundle lookup.

This is the smallest Apple-native approach and fits FitFight's iOS 17+ SwiftUI app. String Catalogs are Apple's current foundation for localization: Xcode extracts supported strings from code, tracks their translation state, supports plural and device variations, and compiles catalogs to the long-supported runtime formats. [Apple: Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) and [WWDC23: Discover String Catalogs](https://developer.apple.com/videos/play/wwdc2023/10155/)

Keep English as the development language. Apple says a language designator without a region is appropriate for a language used in many regions, and specifically presents French (`fr`) as a valid language-only localization. Use a region-specific localization only when the copy truly differs by region. [Apple: `CFBundleDevelopmentRegion`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledevelopmentregion) and [Apple: String Catalog localizations](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)

## Current FitFight state

The project is prepared for extraction but is not localized yet:

- [`project.pbxproj`](../../FitFight.xcodeproj/project.pbxproj) already has `SWIFT_EMIT_LOC_STRINGS = YES` and `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`. These are the Apple-recommended compiler extraction and catalog export settings.
- The project's development region is `en`, but `knownRegions` contains only `en` and `Base`.
- There is no `.xcstrings`, `.strings`, or `.stringsdict` resource.
- Roughly 259 SwiftUI text/control/accessibility call sites exist, before counting user-visible strings assembled in models and stores.
- The generated Info.plist values include English `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` strings in both build configurations.
- [`ios-screenshots.yml`](../../.github/workflows/ios-screenshots.yml) launches the screenshot build without a language override, so the current App Store screenshot artifact covers only the default language.
- [`metadata.md`](../app-store/metadata.md), the privacy page, and the support page currently provide English copy only.

Adding a catalog alone will not translate the whole app. FitFight has three separate categories of text that need distinct handling.

| FitFight text | Correct treatment |
| --- | --- |
| Static interface copy, status copy, validation errors, Health state, accessibility labels, changelog notes | Localize through the catalog |
| Usernames, display names, Fight names, and the user-written loser action | Display verbatim; never treat them as localization keys |
| Dates, numbers, counts, durations, ordinals, and lists | Format with locale-aware Foundation APIs inside complete localizable messages |

## SwiftUI and custom components

SwiftUI automatically treats a literal passed to APIs such as `Text`, `Button`, `Label`, `Toggle`, and `Picker` as a `LocalizedStringKey`. A `String` variable passed to the corresponding initializer is displayed verbatim, which is normally correct for user-provided content. [Apple: `LocalizedStringKey`](https://developer.apple.com/documentation/swiftui/localizedstringkey) and [Apple: Preparing views for localization](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization)

That distinction exposes FitFight's largest implementation issue. Many design-system views in [`Components.swift`](../../FitFight/DesignSystem/Components.swift), [`Controls.swift`](../../FitFight/DesignSystem/Controls.swift), and [`AppChrome.swift`](../../FitFight/DesignSystem/AppChrome.swift) accept labels as plain `String`, then call `Text(title)` or `Text(text)`. A literal such as `FFButton(title: "Next", ...)` has already become a runtime `String` at that boundary, so SwiftUI does not automatically look it up.

Apple recommends `LocalizedStringResource` for representing and passing localizable text through custom views. Static-copy inputs such as `FFButton.title`, `FFSectionHeader.title`, `FFGroupedRow.title`, `FFPill.text`, and similar labels should use that type, or receive a `Text` content builder when the component also needs rich content. Keep a deliberate verbatim path for user/server values. [WWDC23: custom views and `LocalizedStringResource`](https://developer.apple.com/videos/play/wwdc2023/10155/?time=498)

Use the APIs by context:

- In a SwiftUI body, keep literal copy in localizable initializers, for example `Text("New fight", comment: "Title of the create-fight flow")`.
- For reusable components that pass static copy around, use `LocalizedStringResource`.
- When an API truly requires a resolved `String` outside SwiftUI, use `String(localized:)`.
- For a username, custom action, API identifier, fight code, or other user/server content, keep `String` and display it verbatim. `Text(verbatim:)` can make that intent explicit.
- Add comments where context affects the French translation: “Fight” as the product's challenge concept, “Steps” as Apple Health step count, “You” as the profile tab, “On” as a state, and short actions such as “Change” or “Back.” Apple recommends comments to remove ambiguity for translators. [Apple: Preparing app text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)

Do not construct a sentence by translating fragments. Keep the whole sentence as one catalog entry and interpolate values so a translator can change word order. This applies to copy such as “You vs …”, “… challenged you”, “Leading by … with … to go”, and “No one with @…”. Apple's internationalization guidance explicitly warns against composing phrases from separate keys because languages differ in word order and agreement. [Apple: Internationalizing your code](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/InternationalizingYourCode/InternationalizingYourCode.html)

## Interpolation, plurals, and variations

Use catalog plural variations rather than Swift branches such as `count == 1 ? "day" : "days"`. String Catalogs derive the required plural categories for each language from an interpolated numeric argument. English and French may share category names, but their rules and wording remain owned by each localization. [Apple: String Catalog plural variations](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) and [Apple: Localizing strings that contain plurals](https://developer.apple.com/documentation/xcode/localizing-strings-that-contain-plurals)

FitFight should convert these first:

- `Fight.durationLabel` and the duplicate duration construction in `AppModel.mapFight`.
- `FightDetailView.timeRemaining`.
- “Step … of 5,” “… steps today,” “… days/hours left,” rank/participant counts, and pending-player copy.
- The English-only ordinal helper (`1st`, `2nd`, `3rd`, `nth`). French ranks should not be produced by an English suffix algorithm; express the complete rank message through localized copy and locale-aware number formatting.

Keep interpolated values typed. Do not pre-render a count with `String(format:)` and insert the resulting text into a catalog key, because that loses automatic plural selection and locale-aware digits. SwiftUI interpolation and `String(localized:)` preserve the runtime arguments needed for formatting and reordering. [WWDC22: Get it right (to left)](https://developer.apple.com/videos/play/wwdc2022/10107/?time=1430)

Use device variations only if wording reflects a genuinely different interaction or device, such as “Tap” versus “Click.” FitFight is currently iPhone-only, so no device variation is needed. Apple recommends Dynamic Type rather than width-specific string variants for layout pressure. [Apple: Creating width and device variants](https://developer.apple.com/documentation/xcode/creating-width-and-device-variants-of-strings)

## Dates, numbers, durations, and lists

Language and region are separate. A person may run FitFight in French while retaining a non-French region's date, time, numbering, and measurement preferences. Do not infer formatting rules from the selected app language.

For visible data, prefer Swift's `formatted(_:)`, Foundation `FormatStyle`, and SwiftUI `Text(_:format:)`. These APIs account for locale conventions and Foundation caches identically configured formatters. Available styles cover dates, intervals, relative dates, numbers, percentages, measurements, lists, and more. [Apple: Data Formatting](https://developer.apple.com/documentation/foundation/data-formatting), [Apple: `FormatStyle`](https://developer.apple.com/documentation/foundation/formatstyle), and [Apple: `Date.FormatStyle`](https://developer.apple.com/documentation/foundation/date/formatstyle)

Specific FitFight corrections:

- Replace user-visible `DateFormatter.dateFormat = "MMM d"`, `"EEE d MMM"`, and the fixed `en_US_POSIX` version date with localized `Date.FormatStyle` output. Keep `en_US_POSIX` only for machine protocols such as stable day stamps; those are not user interface text.
- Replace `String(format: "%.1fk", ...)` and `"%.0f"` for visible scores with a number format style. Decide whether compact notation is still legible and accurate for a competitive score; full grouped totals are safest where exact steps matter.
- Use `Date.IntervalFormatStyle` for a visible fight range, `Date.RelativeFormatStyle` or localized plural messages for remaining time, and `ListFormatStyle` for multiple opponent names rather than joining with English punctuation or conjunctions.
- Keep ISO 8601 formatting for API payloads. Protocol serialization must stay stable and locale-independent.

## Language selection

Once the bundle contains English and French localizations, iOS selects the best supported language from the person's preferences. Multilingual users can also choose a language for FitFight independently of the device language in Settings. Apple says not to set the application language manually in code; the system also handles language and font fallback. If the app exposes a language control, Apple recommends sending the user to the app's system Settings rather than implementing another language engine. [WWDC19: Creating Great Localized Experiences](https://developer.apple.com/videos/play/wwdc2019/403/?time=170)

Recommended FitFight behavior:

- Do not add an in-app English/French picker.
- Set `UIPrefersShowingLanguageSettings = YES` if Marc wants the Language row to remain visible in FitFight's system Settings even when the person has only one preferred language. Without it, iOS automatically exposes per-app language selection to people with multiple preferred languages. [WWDC24: Build multilingual-ready apps](https://developer.apple.com/videos/play/wwdc2024/10185/?time=890)
- If a permanent Language row is desired under You → Settings, make it open FitFight's system Settings; do not store a language in `UserDefaults`.
- For any future localized server-owned content, determine the running app language using bundle localization matching, not `Locale.preferredLanguages.first`, which can return a language the app does not support. [WWDC19: bundle language matching](https://developer.apple.com/videos/play/wwdc2019/403/?time=240)

User-generated Fight text stays in the language its author wrote. FitFight should not translate usernames, names, or loser actions and should not advertise automatic translation.

## Info.plist, privacy prompts, and accessibility

Create `InfoPlist.xcstrings`, add it to the app target's Resources build phase, and build so Xcode extracts known localizable Info.plist keys. Apple specifically directs multilingual apps to localize every protected-resource purpose string this way. [Apple: Requesting access to protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources) and [WWDC23: Info.plist extraction](https://developer.apple.com/videos/play/wwdc2023/10155/?time=618)

For FitFight, translate both `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` into French. Keep the English values in build settings as source/fallback values. Each localization must remain accurate, meaningful, specific, concise, and normally a complete sentence; App Review checks localized purpose strings too. `CFBundleDisplayName` can remain `FitFight` in both languages, but it should be present if the catalog workflow extracts it.

Localize custom VoiceOver labels, values, hints, and accessibility action names just like visible text. SwiftUI's accessibility label APIs accept localized resources/keys. Keep `accessibilityIdentifier` values stable and untranslated because UI automation uses them as identifiers, not spoken copy. Accessibility labels should be short and should not repeat the control type, such as “Save” rather than “Save button.” [Apple: SwiftUI `accessibilityLabel`](https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)) and [Apple: UIKit accessibility label guidance](https://developer.apple.com/documentation/uikit/uiaccessibilityelement/accessibilitylabel)

In the current app, this includes “Sign in with Apple,” “Step … of 5,” and “Remove @…”. Interpolate the username verbatim into the localized accessibility sentence. Also verify that images containing text do not exist; if a future asset contains language-specific text, Apple supports localized variants in asset catalogs. [Apple: Localizing assets in a catalog](https://developer.apple.com/documentation/xcode/localizing-assets-in-a-catalog)

## Translation workflow

For the initial two-language implementation:

1. Add `Localizable.xcstrings` and `InfoPlist.xcstrings` to the explicit Xcode project file and app Resources phase.
2. Add French (`fr`) to the project/catalog and keep English as the source language.
3. Repair the plain-`String` custom component boundaries and convert model/store-generated interface messages to localizable resources or `String(localized:)`.
4. Build every app target so compiler extraction populates and synchronizes the catalogs. Xcode marks newly discovered strings, changed translations needing review, and stale translated entries. [WWDC23: catalog synchronization and states](https://developer.apple.com/videos/play/wwdc2023/10155/?time=671)
5. Add French translations, plural variations, and contextual comments. Require both catalogs to show complete, reviewed French coverage before shipping.
6. Review the translation in context with a native French speaker. Product words such as “Fight,” “Steps,” “You,” “loser action,” and “standings” need consistent decisions rather than isolated literal translation.

For external translation, export from Product → Export Localizations or use `xcodebuild -exportLocalizations`. Xcode produces an `.xcloc` package containing XLIFF and contextual source resources. Import the completed localization through Xcode or `xcodebuild -importLocalizations`; catalog translations are merged into the corresponding `.xcstrings` files. Add screenshots to the export when useful to the translator. [Apple: Exporting localizations](https://developer.apple.com/documentation/xcode/exporting-localizations), [Apple: Importing localizations](https://developer.apple.com/documentation/xcode/importing-localizations), and [Apple: Editing XLIFF and string catalogs](https://developer.apple.com/documentation/xcode/editing-xliff-and-string-catalog-files)

Do not use raw machine translation as the shipping review standard for Health, privacy, account deletion, or destructive actions. These strings need semantic review in their actual screens.

## Verification gates

Apple recommends testing every supported language and region, not merely checking that translation files exist. Xcode can run a scheme with a chosen App Language and App Region, while SwiftUI previews can override `\.locale`. [Apple: Testing localizations when running](https://developer.apple.com/documentation/xcode/testing-localizations-when-running-your-app) and [Apple: Previewing localizations](https://developer.apple.com/documentation/xcode/previewing-localizations)

Before a localized TestFlight build:

- Build successfully with both catalogs in the target and verify the built app advertises `en` and `fr` localizations.
- Run the full signed-in flow in English and French: welcome/sign-in, username, Health connection, fights list, invite accept/decline, creation, detail/standings, You settings, deletion confirmation, errors, and Versions.
- Test at least English + representative English regions and French with `fr-FR`. Region tests must demonstrate that the app language and formatting locale can differ.
- Test plural boundaries `0`, `1`, `2`, and a larger value for hours, days, steps, players, pending invitations, and ranks.
- Use Xcode's **Show non-localized strings** diagnostic, which displays missed interface strings in uppercase.
- Run **Double-Length**, **Accented**, **Tall**, and **Bounded String** pseudolanguages to expose clipping, insufficient vertical space, and unlocalized text. Apple's current Xcode list also includes right-to-left diagnostics; they are useful regression coverage even though English and French are left-to-right. [Apple: Preparing the interface for localization](https://developer.apple.com/documentation/xcode/preparing-your-interface-for-localization)
- Test Dynamic Type and VoiceOver in both languages, including icon-only controls and interpolated accessibility labels.
- Test changing FitFight's per-app language in Settings and returning to the same usable state after the system relaunches it.
- Extend screenshot CI to render and retain a French set, then validate that no French text is clipped. Use fictional usernames/actions and no real Health data, as the current English screenshot workflow does.
- Have a native French speaker use the resulting staging build in TestFlight. Apple recommends beta feedback from native speakers for supported languages. [Apple: Localization overview](https://developer.apple.com/documentation/xcode/localization)

## Changelog and persisted/cached content

The permanent Versions screen makes all visible [`Changelog.swift`](../../FitFight/Changelog.swift) notes part of the localization scope. They are currently plain English `String` values, so each visible release note needs a stable localized resource. Do not localize version numbers or dates as prose; format the date by locale and localize only the note text and labels such as “this build.”

Cached fights currently store several preformatted English presentation fields (`durationLabel`, kicker fragments, list subtitles, and ended labels). A language change can therefore leave cached content in the old language. Presentation strings should be derived from typed fight data at display time, or the cache must store language-neutral values and be remapped after launch. Avoid persisting resolved localized strings.

The `prod`/`staging` version markers and fight IDs are technical identifiers and can remain verbatim. Human framing around them, including “build,” should be localized while preserving the required version-label position and content.

## App Store and public pages

Binary localization and App Store metadata localization are separate. Adding French in Xcode does not create a French App Store product page. In App Store Connect, add the appropriate French metadata localization and supply localized name/subtitle, promotional text, description, keywords, release notes, privacy-policy URL where applicable, and screenshots. If no matching localization exists, App Store Connect falls back to another relevant localization or the primary language. [Apple: Localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information)

Apple permits localized screenshots and previews. Provide real French screenshots instead of allowing the English screenshot set to default into the French listing; the screen content should match the French binary. [Apple: Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots) and [Apple: Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)

The in-app Privacy and Support rows currently open English-only web pages. A coherent French experience needs French versions or language-negotiated versions of those same approved surfaces, and the French App Store localization should point to the appropriate privacy/support content. This does not authorize building broader website surfaces.

Keep English as the App Store primary language unless Marc deliberately decides otherwise. App Store Connect has separate approval and screenshot prerequisites before changing the primary metadata language; adding French does not require changing it. [Apple: Change the primary language](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information#change-the-primary-language)

## Suggested delivery stages

1. **Localization foundation:** add both catalogs and `fr`, fix custom component types, preserve explicit verbatim paths, and make extraction complete.
2. **Dynamic language correctness:** replace manual English status/plural/date/ordinal construction, localize errors and release notes, and stop caching preformatted localized presentation.
3. **Translation and native review:** translate the binary and Health prompts, review terminology and destructive/privacy copy, and clear catalog review states.
4. **Cloud verification:** compile in GitHub CI, add English/French screenshot coverage, run the localization matrix, and ship the staging build through the existing non-`main` TestFlight path.
5. **Storefront completeness:** add French App Store metadata/screenshots and French privacy/support content before the public localized release.

Success means one binary follows iOS's English/French choice without a custom language store, every app-owned interface and VoiceOver string changes consistently, user-generated content remains untouched, values follow the person's region settings, Apple Health prompts are localized, cached screens cannot mix old and new languages, and the French App Store page accurately shows the French app.
