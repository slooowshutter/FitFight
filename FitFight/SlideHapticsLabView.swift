import SwiftUI

/// Marc-only playground for Slide to start vibrations. Hidden from every other account.
struct SlideHapticsLabView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FFSlideHapticRecipe.storageKey) private var selectedRecipeID = FFSlideHapticRecipe.shippedID
    @State private var editingCustom = false
    @State private var custom = FFCustomSlideHaptics.restore(
        from: UserDefaults.standard.data(forKey: FFCustomSlideHaptics.storageKey)
    )
    @State private var saveFailed = false

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: "Slide haptics") { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)

            Text(verbatim: "Try 20 presets or tune your own. Strength and crispness use 0-100. Custom settings save automatically on this phone, even when you use a preset.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 12)

            FFSegmented(items: [false, true], selection: $editingCustom) { $0 ? "Custom" : "Presets" }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if editingCustom {
                        rumbleControls
                        tickControls
                        finishControls
                    } else {
                        ForEach(FFSlideHapticRecipe.all) { recipe in
                            recipeCard(recipe)
                        }
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .tint(theme.mossFill)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editingCustom {
                customPreview
            }
        }
        .onAppear {
            editingCustom = selectedRecipeID == FFCustomSlideHaptics.recipeID
        }
    }

    private var settings: Binding<FFCustomSlideHaptics> {
        Binding(get: { custom }, set: { value in
            custom = value
            do {
                try value.save()
                saveFailed = false
            } catch {
                saveFailed = true
            }
        })
    }

    private var rumbleControls: some View {
        FFCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: settings.rumbleEnabled) {
                    Text(verbatim: "Continuous rumble").ffType(.heading)
                }
                .frame(minHeight: 44)
                if custom.rumbleEnabled {
                    parameter("Start strength", value: settings.rumble.intensityStart)
                    parameter("End strength", value: settings.rumble.intensityEnd)
                    parameter("Start crispness", value: settings.rumble.sharpnessStart)
                    parameter("End crispness", value: settings.rumble.sharpnessEnd)
                    parameter("Strength ramp", value: settings.rumble.intensityPower, range: 0.25...4, step: 0.25, scale: 1)
                    parameter("Crispness ramp", value: settings.rumble.sharpnessPower, range: 0.25...4, step: 0.25, scale: 1)
                    Text(verbatim: "Ramp 1 rises evenly. Below 1 builds early; above 1 saves the strongest change for the end.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .foregroundStyle(theme.text)
        }
    }

    private var tickControls: some View {
        FFCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: settings.ticksEnabled) {
                    Text(verbatim: "Ticks and pulses").ffType(.heading)
                }
                .frame(minHeight: 44)
                if custom.ticksEnabled {
                    Picker(selection: settings.systemImpacts) {
                        Text(verbatim: "Texture").tag(false)
                        Text(verbatim: "Impact").tag(true)
                    } label: {
                        Text(verbatim: "Tick type")
                    }
                    .pickerStyle(.segmented)
                    if custom.systemImpacts {
                        impactPicker("Tick impact", selection: settings.impactStyle)
                    }
                    Picker(selection: settings.timedTicks) {
                        Text(verbatim: "Along the track").tag(false)
                        Text(verbatim: "On a clock").tag(true)
                    } label: {
                        Text(verbatim: "Pulse timing")
                    }
                    .pickerStyle(.segmented)
                    if custom.timedTicks {
                        parameter("Start pulses / second", value: settings.startHz, range: 0.5...60, step: 0.5, scale: 1)
                        parameter("End pulses / second", value: settings.endHz, range: 0.5...60, step: 0.5, scale: 1)
                        Stepper(value: settings.movementCount, in: 0...64) {
                            Text(verbatim: "Extra track ticks: \(custom.movementCount)")
                        }
                        .frame(minHeight: 44)
                        Text(verbatim: "Extra ticks react to movement during a fast swipe. Set to 0 for timed pulses only.")
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Stepper(value: settings.tickCount, in: 1...64) {
                            Text(verbatim: "Track ticks: \(custom.tickCount)")
                        }
                        .frame(minHeight: 44)
                    }
                    tickStrengthControls
                }
            }
            .ffType(.label)
            .foregroundStyle(theme.text)
        }
    }

    private var tickStrengthControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            parameter("Start tick strength", value: settings.tickIntensityStart)
            parameter("End tick strength", value: settings.tickIntensityEnd)
            if !custom.systemImpacts {
                parameter("Start tick crispness", value: settings.tickSharpnessStart)
                parameter("End tick crispness", value: settings.tickSharpnessEnd)
            }
            parameter("Tick ramp", value: settings.tickPower, range: 0.25...4, step: 0.25, scale: 1)
        }
    }

    private var finishControls: some View {
        FFCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "Confirmation").ffType(.heading)
                parameter("Confirm at % of track", value: settings.confirmationProgress, range: 50...100)
                Text(verbatim: "The ramp reaches its end value here. Lift your finger to confirm.")
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                Toggle(isOn: settings.finishEnabled) {
                    Text(verbatim: "Finishing hit").ffType(.label)
                }
                .frame(minHeight: 44)
                if custom.finishEnabled {
                    impactPicker("Finish impact", selection: settings.finish.style)
                    parameter("Finish strength", value: settings.finish.intensity)
                }
            }
            .foregroundStyle(theme.text)
        }
    }

    private var customPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: saveFailed ? "Could not save your settings. Change a value to try again." : "Changes save automatically on this phone.")
                .ffType(.caption)
                .foregroundStyle(saveFailed ? theme.emberText : theme.textSecondary)
            FFSlideToConfirm(title: "Slide to test custom", recipe: custom.recipe, resetsAfterSuccess: true) { true }
            if selectedRecipeID == FFCustomSlideHaptics.recipeID {
                Text(verbatim: "Custom is on Slide to start. Changes apply automatically.")
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
            } else {
                FFButton(title: "Use custom on Slide to start", kind: .ghost, size: .small, enabled: !saveFailed) {
                    do {
                        try custom.save()
                        selectedRecipeID = FFCustomSlideHaptics.recipeID
                        saveFailed = false
                    } catch {
                        saveFailed = true
                    }
                }
            }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.vertical, 12)
        .background(theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    private func parameter<Value: BinaryFloatingPoint>(
        _ title: String,
        value: Binding<Value>,
        range: ClosedRange<Double> = 0...100,
        step: Double = 1,
        scale: Double = 100
    ) -> some View {
        let displayed = Double(value.wrappedValue) * scale
        let formatted = displayed.formatted(.number.precision(.fractionLength(0...2)))
        return VStack(spacing: 0) {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(verbatim: formatted).monospacedDigit()
            }
            .ffType(.label)
            Slider(
                value: Binding(get: { Double(value.wrappedValue) * scale }, set: { value.wrappedValue = Value($0 / scale) }),
                in: range,
                step: step
            ) {
                Text(verbatim: title)
            }
            .frame(minHeight: 44)
            .accessibilityValue(Text(verbatim: formatted))
        }
    }

    private func impactPicker(_ title: String, selection: Binding<FFSlideHapticRecipe.ImpactStyle>) -> some View {
        Picker(selection: selection) {
            ForEach(FFSlideHapticRecipe.ImpactStyle.allCases, id: \.self) { style in
                Text(verbatim: style.rawValue.capitalized).tag(style)
            }
        } label: {
            Text(verbatim: title)
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
        .ffType(.label)
    }

    private func recipeCard(_ recipe: FFSlideHapticRecipe) -> some View {
        let selected = recipe.id == selectedRecipeID
        return FFCard(padding: 16, stroke: selected ? theme.mossEdge : nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: recipe.name)
                        .ffType(.heading)
                        .foregroundStyle(selected ? theme.mossText : theme.text)
                    if recipe.id == FFSlideHapticRecipe.shippedID {
                        FFPill("default")
                    }
                    if selected {
                        FFPill("on Slide to start")
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: recipe.summary)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FFSlideToConfirm(
                    title: "Slide to test",
                    recipe: recipe,
                    resetsAfterSuccess: true
                ) {
                    true
                }
                if !selected {
                    FFButton(title: "Use on Slide to start", kind: .ghost, size: .small) {
                        selectedRecipeID = recipe.id
                    }
                }
            }
        }
        .background(
            selected ? theme.mossWash : .clear,
            in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        )
    }
}
