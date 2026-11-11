import AVKit
import ClipperKit
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @State private var model = StudioModel()
    @State private var importing = false
    @State private var preview: PreviewItem?
    @State private var showingAbout = false
    @State private var pane = WorkspacePane.recording
    @State private var selectedID: Int?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 46.0

    private var palette: TidePalette { TidePalette(dark: colorScheme == .dark) }
    private var selectedClip: ClipResult? {
        model.results.first(where: { $0.id == selectedID }) ?? model.results.first
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 780 || dynamicType.isAccessibilitySize
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        topBar
                        heading(compact: compact)
                        if compact {
                            featuredMoment
                            workspace.id("workspace")
                        } else {
                            HStack(alignment: .top, spacing: 30) {
                                featuredMoment.frame(maxWidth: .infinity)
                                workspace.frame(maxWidth: .infinity).id("workspace")
                            }
                        }
                        activity
                        privacyNote
                    }
                    .padding(compact ? 22 : 38)
                    .frame(maxWidth: 1200, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    floatingDock(compact: compact) { destination in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            pane = destination
                            if compact { scroll.scrollTo("workspace", anchor: .top) }
                        }
                    }
                    .padding(.horizontal, compact ? 14 : 30)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                }
            }
        }
        .background(TideBackdrop(palette: palette).ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .audio] + ["mkv", "webm"].compactMap { UTType(filenameExtension: $0) }) { result in
            switch result {
            case .success(let url):
                model.mode = .recording
                pane = .recording
                model.importRecording(url)
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .alert("Unable to finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(item: $preview) { item in PreviewView(url: item.url) }
        .sheet(isPresented: $showingAbout) { aboutSheet }
        .task { await model.refreshAvailability() }
        .onChange(of: model.results.map(\.id)) { _, ids in
            selectedID = ids.first
            if !ids.isEmpty { pane = .moments }
        }
        .onChange(of: model.mode) { _, _ in
            model.resetResults()
            selectedID = nil
        }
    }

    private var topBar: some View {
        HStack {
            Label("clipper", systemImage: "scissors")
                .font(.title2.weight(.semibold))
                .tracking(-0.6)
                .accessibilityLabel("Clipper")
            Spacer(minLength: 12)
            Button { importing = true } label: {
                Label("New recording", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 36)
            }
            .modifier(TideControlStyle(prominent: false))
            .disabled(model.busy)
        }
    }

    private func heading(compact: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Less footage.\nMore feeling.")
                    .font(.system(size: compact ? headingSize * 0.85 : headingSize, weight: .medium, design: .rounded))
                    .tracking(-1.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(model.results.isEmpty
                     ? "A few moments can say everything.\nStart with your recording."
                     : "A few moments can say everything.\nHere are yours.")
                    .font(.callout)
                    .foregroundStyle(palette.secondary)
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
            if !compact {
                Label("Made on your device", systemImage: "checkmark.shield")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .modifier(TideGlassSurface(radius: 30, palette: palette))
            }
        }
    }

    private var featuredMoment: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let clip = selectedClip, let exported = model.exports[clip.id] {
                TidePlayer(url: exported)
                    .clipShape(RoundedRectangle(cornerRadius: 23))
                    .accessibilityLabel("Exported moment \(clip.id + 1)")
            } else if let source = model.recording, model.mode == .recording {
                VStack(alignment: .leading, spacing: 9) {
                    TidePlayer(url: source)
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                    Label("Original recording", systemImage: "play.rectangle")
                        .font(.caption)
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 8)
                }
            } else if let clip = selectedClip {
                Text(clip.text)
                    .font(.title3.weight(.medium))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                    .background(palette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 23))
            } else {
                emptyArtwork
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedClip == nil ? "YOUR ON-DEVICE STUDIO" : "YOUR SELECTED MOMENT")
                        .font(.caption2.weight(.semibold)).tracking(1.3)
                    Spacer()
                    if let clip = selectedClip {
                        Text(durationLabel(clip)).font(.caption).monospacedDigit()
                    }
                }
                .foregroundStyle(palette.secondary)
                if let clip = selectedClip {
                    Text("Moment \(clip.id + 1)")
                        .font(.title3.weight(.semibold))
                    if model.mode == .recording {
                        Text(clip.text)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                        if let first = clip.ranges.first, let last = clip.ranges.last {
                            Label("\(timeLabel(first.start)) – \(timeLabel(last.end)) in the original", systemImage: "clock")
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                        if model.exports[clip.id] == nil {
                            Text("Export this moment to preview the cut.")
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                    }
                    featuredActions(clip)
                } else {
                    Text(model.recording == nil || model.mode == .transcript ? "Make space for a good story." : "Ready for the good parts.")
                        .font(.title3.weight(.semibold))
                    Text(model.mode == .recording
                         ? model.recording?.lastPathComponent ?? "Import spoken audio or video. Find the moments worth keeping."
                         : "Paste a transcript to discover its strongest moments.")
                        .font(.callout).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .padding(12)
        .modifier(TideCard(palette: palette, radius: 32))
    }

    private var emptyArtwork: some View {
        VStack(spacing: 19) {
            Spacer(minLength: 14)
            Image(systemName: model.mode == .recording ? "waveform" : "text.alignleft")
                .font(.system(size: 55, weight: .ultraLight))
                .foregroundStyle(palette.accent)
                .padding(27)
                .background(palette.card.opacity(0.5), in: Circle())
                .overlay(Circle().strokeBorder(palette.edge, lineWidth: 1))
                .accessibilityHidden(true)
            Text("Every story has\na moment.")
                .font(.system(.title, design: .rounded, weight: .medium))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            if model.mode == .recording {
                Button { importing = true } label: {
                    Label("Import recording", systemImage: "plus")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 9).frame(minHeight: 36)
                }
                .modifier(TideControlStyle(prominent: true))
                .disabled(model.busy)
            }
            Spacer(minLength: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 285)
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(colors: [palette.artwork, palette.card.opacity(0.65), palette.artwork.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    @ViewBuilder private func featuredActions(_ clip: ClipResult) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { clipActions(clip) }
            VStack(alignment: .leading, spacing: 12) { clipActions(clip) }
        }
        .font(.callout)
        .padding(.top, 4)
    }

    @ViewBuilder private func clipActions(_ clip: ClipResult) -> some View {
        if let exported = model.exports[clip.id] {
            ShareLink(item: exported) { Label("Save or share", systemImage: "square.and.arrow.up") }
                .modifier(TideControlStyle(prominent: true))
            Button("Preview") { preview = PreviewItem(url: exported) }
                .modifier(TideControlStyle(prominent: false))
        }
        ShareLink(item: clip.text) { Label("Share text", systemImage: "text.quote") }
            .modifier(TideControlStyle(prominent: false))
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text(pane.title).font(.title3.weight(.semibold)).tracking(-0.3)
                Spacer()
                if pane == .moments {
                    Text("\(model.results.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(palette.card.opacity(0.6), in: Capsule())
                }
            }
            switch pane {
            case .recording: recordingControls
            case .moments: momentsList
            case .transcript: transcriptPanel
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 21) {
            Text("Bring a recording. We’ll find the moments.")
                .font(.callout).foregroundStyle(palette.secondary)
            Picker("Input", selection: $model.mode) {
                ForEach(StudioModel.InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.mode == .recording {
                HStack(spacing: 13) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.title2).frame(width: 44, height: 50)
                        .background(palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.recording?.lastPathComponent ?? "Your recording goes here")
                            .font(.callout.weight(.medium)).lineLimit(2)
                        Text("Audio or video · processed locally")
                            .font(.caption).foregroundStyle(palette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Button(model.recording == nil ? "Choose a recording" : "Replace recording", systemImage: "folder") { importing = true }
                    .modifier(TideControlStyle(prominent: false))
                Picker("Spoken language", selection: $model.language) {
                    ForEach(ClipperEngine.supportedLanguages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                    }
                    Text("Other / unsupported").tag("unsupported")
                }
                Text(model.language == "unsupported"
                     ? "Use Transcript mode for this language. Automatic transcription supports 25 languages."
                     : "Choose the spoken language to check transcription support.")
                    .font(.caption).foregroundStyle(palette.secondary)
            } else {
                transcriptEditor
            }
            Divider().overlay(palette.edge)
            Stepper("Up to \(model.limit) highlights", value: $model.limit, in: 1...20)
            Text("A maximum, not a quota. Short recordings may yield fewer moments.")
                .font(.caption).foregroundStyle(palette.secondary)
            Button("Find highlights", systemImage: "sparkles", action: model.select)
                .modifier(TideControlStyle(prominent: true))
                .disabled(!model.canSelect)
            Button("Prepare for offline use", systemImage: "arrow.down.circle", action: model.prepare)
                .modifier(TideControlStyle(prominent: false))
            Text("First use downloads the models. Keep the app open while it processes.")
                .font(.caption).foregroundStyle(palette.secondary)
        }
        .padding(22)
        .modifier(TideCard(palette: palette, radius: 25))
        .disabled(model.busy)
    }

    @ViewBuilder private var momentsList: some View {
        if model.results.isEmpty {
            VStack(alignment: .leading, spacing: 17) {
                Image(systemName: "sparkles").font(.largeTitle).accessibilityHidden(true)
                Text(model.hasRun ? "Give the story a little more room." : "The good parts will land here.")
                    .font(.headline)
                Text(model.hasRun ? "No moments were selected. Try a longer recording or transcript." : "Import a recording or paste a transcript, then find your highlights.")
                    .font(.callout).foregroundStyle(palette.secondary)
                Button("Go to recording", systemImage: "arrow.left") { pane = .recording }
                    .modifier(TideControlStyle(prominent: false))
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TideCard(palette: palette, radius: 25))
        } else {
            Text("Ranked for you. Ready to make yours.")
                .font(.callout).foregroundStyle(palette.secondary)
            ForEach(model.results) { clip in
                momentRow(clip)
            }
            if model.mode == .recording {
                if let reel = model.reel {
                    ShareLink(item: reel) { Label("Save or share reel", systemImage: "square.and.arrow.up") }
                        .modifier(TideControlStyle(prominent: true))
                    Button("Preview reel") { preview = PreviewItem(url: reel) }
                        .modifier(TideControlStyle(prominent: false))
                } else {
                    Button("Export highlight reel", systemImage: "film.stack", action: model.exportReel)
                        .modifier(TideControlStyle(prominent: false)).disabled(model.busy)
                }
                Text("Original framing. Best moments first.")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
        }
    }

    private func momentRow(_ clip: ClipResult) -> some View {
        let selected = selectedClip?.id == clip.id
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = clip.id }
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(String(format: "%02d", clip.id + 1)).font(.callout.weight(.semibold).monospacedDigit())
                    Image(systemName: "waveform").font(.caption)
                }
                .frame(width: 44, height: 54)
                .background(palette.artwork.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 7) {
                    Text(clip.text).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(durationLabel(clip)).font(.caption).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? palette.accent : palette.secondary.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card.opacity(selected ? 0.92 : 0.42), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? palette.accent.opacity(0.65) : palette.edge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Moment \(clip.id + 1). \(clip.text). \(durationLabel(clip))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.mode == .transcript {
                transcriptEditor
                Text("Return to Recording to change the highlight limit.")
                    .font(.caption).foregroundStyle(palette.secondary)
            } else if model.text.isEmpty {
                Text("Your transcript appears here after the recording is analyzed.")
                    .font(.body).foregroundStyle(palette.secondary)
                Button("Use a pasted transcript") {
                    model.mode = .transcript
                    pane = .recording
                }
                .modifier(TideControlStyle(prominent: false)).disabled(model.busy)
            } else {
                Text("The words behind your moments.").font(.callout).foregroundStyle(palette.secondary)
                Text(model.text).font(.body).lineSpacing(6).textSelection(.enabled)
                ShareLink(item: model.text) { Label("Share transcript", systemImage: "square.and.arrow.up") }
                    .modifier(TideControlStyle(prominent: false))
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TideCard(palette: palette, radius: 25))
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste your transcript in spoken order.").font(.callout.weight(.medium))
            TextEditor(text: Binding(get: { model.text }, set: {
                model.text = $0
                model.resetResults()
            }))
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 190)
            .padding(10)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.edge))
            .accessibilityLabel("Recording transcript")
            .disabled(model.busy)
            Text("At least three sentences. Text-only results use estimated durations and cannot export media.")
                .font(.caption).foregroundStyle(palette.secondary)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.busy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.status).font(.callout.weight(.medium))
                }
                if let fraction = model.progress { ProgressView(value: fraction) }
            } else {
                Label(model.status, systemImage: model.hasRun ? "checkmark.circle" : "leaf")
                    .font(.callout)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { modelBadges }
                VStack(alignment: .leading, spacing: 8) { modelBadges }
            }
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var modelBadges: some View {
        Label(model.clipsDownloaded ? "Clips ready" : "Clips · download about 284 MB", systemImage: model.clipsDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.caption)
        Label(model.vozDownloaded ? "Transcriber ready" : "Transcriber · download about 467 MB", systemImage: model.vozDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.caption)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield").accessibilityHidden(true)
            Text("Your recordings stay on this device. Model downloads and SDK usage metadata use the internet.")
                .font(.caption)
            Spacer(minLength: 0)
            Button { showingAbout = true } label: { Image(systemName: "info.circle").frame(minWidth: 32, minHeight: 32) }
                .modifier(TideControlStyle(prominent: false)).accessibilityLabel("About local processing and exports")
        }
        .foregroundStyle(palette.secondary)
    }

    private func floatingDock(compact: Bool, navigate: @escaping (WorkspacePane) -> Void) -> some View {
        TideGlassGroup {
            ViewThatFits(in: .horizontal) {
                dockContent(iconOnly: compact, navigate: navigate)
                dockContent(iconOnly: true, navigate: navigate)
            }
            .padding(7)
            .modifier(TideGlassSurface(radius: 36, palette: palette))
            .shadow(color: palette.shadow, radius: 20, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func dockContent(iconOnly: Bool, navigate: @escaping (WorkspacePane) -> Void) -> some View {
        HStack(spacing: 5) {
            TideSlidingTabs(selection: pane, iconOnly: iconOnly, palette: palette, navigate: navigate)
            Divider().frame(height: 24).padding(.horizontal, 3)
            dockAction
        }
    }

    @ViewBuilder private var dockAction: some View {
        if let clip = selectedClip {
            if let exported = model.exports[clip.id] {
                ShareLink(item: exported) { dockLabel("Share clip", symbol: "square.and.arrow.up") }
                    .modifier(TideControlStyle(prominent: true))
            } else if !clip.ranges.isEmpty {
                Button { model.export(clip) } label: { dockLabel("Export clip", symbol: "square.and.arrow.up") }
                    .modifier(TideControlStyle(prominent: true)).disabled(model.busy)
            } else {
                ShareLink(item: clip.text) { dockLabel("Share text", symbol: "text.quote") }
                    .modifier(TideControlStyle(prominent: true))
            }
        } else {
            Button(action: model.select) { dockLabel(model.busy ? "Working…" : "Find highlights", symbol: "sparkles") }
                .modifier(TideControlStyle(prominent: true)).disabled(!model.canSelect)
        }
    }

    private func dockLabel(_ label: String, symbol: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 17)
            .frame(minHeight: 44)

    }

    private var aboutSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your device. Your ideas.").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { showingAbout = false }
            }
            Text("Clips finds highlights in transcripts. Voz transcribes recordings. Both models run locally after their initial downloads.")
            Text("The SDK sends usage metadata when connected. Recordings and transcript content are processed on your device.")
            Text("Exports keep the original framing: MOV for video and M4A for audio. Save or share exports before replacing the recording. This workspace is temporary.")
            // Required by the Desert Ant Labs Source-Available License: https://license.desertant.com/attribution
            Text("Clips and Voz models by [Desert Ant Labs](https://desertant.com), under the [Desert Ant Labs Source-Available License](https://license.desertant.com/1.0). Video conversion by [FFmpeg](https://ffmpeg.org).")
                .font(.callout)
            Text("Tide uses native Liquid Glass on iOS 26 and macOS 26, with material fallbacks on older supported versions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(idealWidth: 490)
        .presentationDetents([.medium, .large])
    }

    private func durationLabel(_ clip: ClipResult) -> String {
        if let seconds = clip.playbackDuration { return "\(Int(seconds.rounded())) sec" }
        return "~\(Int(clip.estimatedDuration.rounded())) sec estimated"
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private enum WorkspacePane: String, CaseIterable, Identifiable {
    case recording = "Recording", moments = "Moments", transcript = "Transcript"
    var id: Self { self }
    var title: String {
        switch self {
        case .recording: "Your next recording"
        case .moments: "Your best moments"
        case .transcript: "The full transcript"
        }
    }
    var symbol: String {
        switch self {
        case .recording: "waveform"
        case .moments: "sparkles"
        case .transcript: "text.alignleft"
        }
    }
}

// A single lens follows a finger or pointer, then springs to the nearest tab.
// The gesture excludes the adjacent action so scrubbing cannot trigger export.
private struct TideSlidingTabs: View {
    let selection: WorkspacePane
    let iconOnly: Bool
    let palette: TidePalette
    let navigate: (WorkspacePane) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var cellWidth = 138.0
    @GestureState private var dragPosition: CGFloat?

    private var width: CGFloat { iconOnly ? 44 : cellWidth }
    private var selectedIndex: Int { WorkspacePane.allCases.firstIndex(of: selection) ?? 0 }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82) }

    var body: some View {
        let position = dragPosition ?? CGFloat(selectedIndex)
        let bulge = reduceMotion ? 0 : sin(position * .pi).magnitude * 7
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.clear)
                .frame(width: width + bulge, height: 44)
                .modifier(TideGlassSurface(radius: 24, palette: palette, interactive: true))
                .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                .offset(x: position * width - bulge / 2)
                .animation(dragPosition == nil ? spring : nil, value: position)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(WorkspacePane.allCases) { destination in
                    Button { navigate(destination) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: destination.symbol)
                            if !iconOnly { Text(destination.rawValue).font(.callout.weight(.medium)) }
                        }
                        .frame(width: width, height: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == destination ? palette.ink : palette.secondary)
                    .accessibilityLabel(destination.rawValue)
                    .accessibilityHint("Switch section. You can also drag across the dock.")
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
        }
        .frame(width: width * 3, height: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .updating($dragPosition) { value, state, transaction in
                    transaction.animation = nil
                    state = progress(at: value.location.x)
                }
                .onEnded { value in
                    navigate(WorkspacePane.allCases[Int(progress(at: value.location.x).rounded())])
                }
        )
    }

    private func progress(at x: CGFloat) -> CGFloat {
        min(2, max(0, x / width - 0.5))
    }
}

private struct TidePalette {
    let dark: Bool
    var ink: Color { dark ? Color(red: 0.88, green: 0.96, blue: 0.91) : Color(red: 0.07, green: 0.24, blue: 0.20) }
    var secondary: Color { dark ? Color(red: 0.66, green: 0.78, blue: 0.72) : Color(red: 0.26, green: 0.40, blue: 0.34) }
    var accent: Color { dark ? Color(red: 0.57, green: 0.83, blue: 0.70) : Color(red: 0.08, green: 0.34, blue: 0.26) }
    var onAccent: Color { dark ? Color(red: 0.04, green: 0.18, blue: 0.13) : .white }
    var card: Color { dark ? Color(red: 0.12, green: 0.23, blue: 0.19) : Color(red: 0.95, green: 0.99, blue: 0.96) }
    var edge: Color { dark ? Color.white.opacity(0.14) : Color.white.opacity(0.8) }
    var artwork: Color { dark ? Color(red: 0.13, green: 0.32, blue: 0.24) : Color(red: 0.64, green: 0.80, blue: 0.72) }
    var backdrop: Color { dark ? Color(red: 0.035, green: 0.105, blue: 0.085) : Color(red: 0.83, green: 0.91, blue: 0.86) }
    var glow: Color { dark ? Color(red: 0.12, green: 0.28, blue: 0.22) : Color(red: 0.66, green: 0.80, blue: 0.74) }
    var shadow: Color { Color.black.opacity(dark ? 0.2 : 0.08) }
}

private struct TideBackdrop: View {
    let palette: TidePalette
    var body: some View {
        palette.backdrop.overlay {
            RadialGradient(colors: [palette.glow, .clear], center: .topTrailing, startRadius: 20, endRadius: 800)
        }
        .overlay {
            RadialGradient(colors: [palette.card.opacity(0.5), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
    }
}

private struct TideCard: ViewModifier {
    let palette: TidePalette
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background(palette.card.opacity(reduceTransparency ? 1 : 0.56), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.edge, lineWidth: 1))
            .shadow(color: palette.shadow, radius: 18, x: 0, y: 8)
    }
}

private struct TideGlassSurface: ViewModifier {
    let radius: CGFloat
    let palette: TidePalette
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(palette.card, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.edge))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(palette.artwork.opacity(0.12)).interactive(interactive), in: .rect(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.edge))
        }
    }
}

private struct TideGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 20) { content() }
        } else { content() }
    }
}

private struct TideControlStyle: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), !reduceTransparency {
            if prominent { content.buttonStyle(.glassProminent).buttonBorderShape(.capsule) }
            else { content.buttonStyle(.glass).buttonBorderShape(.capsule) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

// Avoid the _AVKit_SwiftUI VideoPlayer metadata crash seen on macOS 26.6.2.
// Both inline and sheet previews share this native AppKit adapter.
#if os(macOS)
private struct ClipperPlayerSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
#else
private struct ClipperPlayerSurface: View {
    let player: AVPlayer?
    var body: some View { VideoPlayer(player: player) }
}
#endif

private struct TidePlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        ClipperPlayerSurface(player: player)
            .aspectRatio(16 / 10, contentMode: .fit)
            .frame(minHeight: 180)
            .task(id: url) {
                player?.pause()
                player = AVPlayer(url: url)
            }
            .onDisappear { player?.pause() }
    }
}

private struct PreviewItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct PreviewView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        NavigationStack {
            ClipperPlayerSurface(player: player)
                .frame(minWidth: 300, minHeight: 300)
                .toolbar { Button("Done") { dismiss() } }
                .onAppear { player = AVPlayer(url: url); player?.play() }
                .onDisappear { player?.pause(); player = nil }
        }
    }
}
