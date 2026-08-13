import SwiftUI

/// 通常モードの「音源」「工程」と同じ役割を持つStem Mode専用サイドバーです。
@MainActor
struct StemModeSidebarView: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection(title: "音源") {
                    SidebarFileRow(
                        title: "入力2mix",
                        systemImage: "waveform",
                        fileURL: model.selectedInputURL,
                        fileInfo: model.selectedInputFileInfo,
                        placeholder: "まだ選択されていません",
                        tint: .blue
                    )
                    SidebarFileRow(
                        title: "補正済み純粋加算",
                        systemImage: "waveform.badge.checkmark",
                        fileURL: model.correctedPureSumPreviewArtifact?.fileURL,
                        fileInfo: fileInfo(for: model.correctedPureSumPreviewArtifact),
                        placeholder: "補正完了後に表示されます",
                        tint: .blue
                    )
                    SidebarFileRow(
                        title: "Stem再ミックス",
                        systemImage: "slider.horizontal.3",
                        fileURL: model.remixedPreviewArtifact?.fileURL,
                        fileInfo: fileInfo(for: model.remixedPreviewArtifact),
                        placeholder: "再ミックス後に表示されます",
                        tint: .green
                    )
                    SidebarFileRow(
                        title: "Stem Mode最終版",
                        systemImage: "waveform.path.ecg.rectangle",
                        fileURL: model.finalPreviewArtifact?.fileURL,
                        fileInfo: fileInfo(for: model.finalPreviewArtifact),
                        placeholder: "マスタリング後に表示されます",
                        tint: .orange
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.availableStemRoles.count) Stem")
                            .font(.callout.bold())
                            .foregroundStyle(.secondary)
                        ForEach(model.availableStemRoles, id: \.self) { role in
                            StemModeSidebarStemRow(
                                role: role,
                                rawArtifact: artifact(kind: .rawStem(role)),
                                correctedArtifact: artifact(kind: .correctedStem(role)),
                                usedRawFallback: model.stemEvaluations
                                    .first(where: { $0.role == role })?.usedRawFallback == true
                            )
                        }
                    }
                }

                sidebarSection(title: "工程") {
                    StemModeSidebarProcessingStatusView(
                        session: model.session,
                        correctionProgresses: model.correctionDisplayProgress
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .velouraTransientOverlayScrollIndicators()
        }
        .scrollContentBackground(.hidden)
    }

    private func sidebarSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func artifact(kind: StemArtifactKind) -> StemAudioArtifact? {
        model.session.artifactStates
            .compactMap(\.artifact)
            .first(where: { $0.kind == kind })
    }

    private func fileInfo(for artifact: StemAudioArtifact?) -> AudioFileInfo? {
        guard let artifact else { return nil }
        return AudioFileInfo(
            formatName: "WAV",
            sampleRate: artifact.sampleRate,
            channelCount: artifact.channelCount,
            duration: artifact.sampleRate > 0
                ? Double(artifact.frameCount) / artifact.sampleRate
                : 0,
            bitDepth: 32,
            isFloatingPoint: true
        )
    }
}

private struct StemModeSidebarStemRow: View {
    let role: StemRole
    let rawArtifact: StemAudioArtifact?
    let correctedArtifact: StemAudioArtifact?
    let usedRawFallback: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: correctedArtifact == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(correctedArtifact == nil ? Color.secondary : Color.green)
                    .accessibilityHidden(true)
                Text(role.stemModeDisplayTitle)
                    .font(.callout.bold())
                Spacer(minLength: 6)
                if usedRawFallback {
                    Text("raw使用")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if let correctedArtifact {
            let rate = correctedArtifact.sampleRate / 1_000
            return "補正済み \(rate.formatted(.number.precision(.fractionLength(1)))) kHz"
        }
        if let rawArtifact {
            let rate = rawArtifact.sampleRate / 1_000
            return "raw \(rate.formatted(.number.precision(.fractionLength(1)))) kHz / 補正待ち"
        }
        return "分離待ち"
    }
}

@MainActor
private struct StemModeSidebarProcessingStatusView: View {
    let session: StemWorkflowSession
    let correctionProgresses: [StemModeProcessStepProgress]

    var body: some View {
        SidebarProcessingStatusListView(sections: sections)
    }

    private var sections: [SidebarProcessStatusSection] {
        [
            statusSection(
                id: "correction",
                title: "補正",
                progresses: correctionProgresses,
                startedAt: session.correctionStartedAt,
                finishedAt: session.correctionFinishedAt,
                isProcessing: session.isCorrectionProcessing
            ),
            statusSection(
                id: "remix",
                title: "再ミックス",
                progresses: session.remixDisplayProgress,
                startedAt: session.remixStartedAt,
                finishedAt: session.remixFinishedAt,
                isProcessing: session.isRemixProcessing
            ),
            statusSection(
                id: "mastering",
                title: "マスタリング",
                progresses: session.masteringDisplayProgress,
                startedAt: session.masteringStartedAt,
                finishedAt: session.masteringFinishedAt,
                isProcessing: session.isMasteringProcessing
            ),
        ]
    }

    private func statusSection(
        id: String,
        title: String,
        progresses: [StemModeProcessStepProgress],
        startedAt: Date?,
        finishedAt: Date?,
        isProcessing: Bool
    ) -> SidebarProcessStatusSection {
        let active = progresses.first(where: { $0.status == .running })
        let failed = progresses.contains(where: { $0.status == .failed })
        let complete = !isProcessing
            && progresses.allSatisfy { $0.status == .completed || $0.status == .skipped }
        let tint: Color = if isProcessing {
            ProcessingStatusColors.active
        } else if failed {
            .red
        } else if complete {
            ProcessingStatusColors.complete
        } else {
            .secondary
        }
        let progress = progresses.isEmpty
            ? 0
            : progresses.map(\.fraction).reduce(0, +) / Double(progresses.count)

        return SidebarProcessStatusSection(
            id: id,
            title: title,
            status: failed ? "失敗" : (isProcessing ? "処理中" : (complete ? "完了" : "待機")),
            activeStepTitle: isProcessing ? active?.step.title : nil,
            activeStepDetail: isProcessing
                ? active?.stemModeSidebarDetail(stemCount: session.runContract?.stemCount ?? 0)
                : nil,
            startedAt: startedAt,
            finishedAt: finishedAt,
            isRunning: isProcessing,
            isComplete: complete,
            hasFailed: failed,
            progress: progress,
            steps: progresses.map(stepDisplay),
            tint: tint
        )
    }

    private func stepDisplay(_ progress: StemModeProcessStepProgress) -> SidebarProcessStepDisplay {
        let state: SidebarProcessStepState
        switch progress.status {
        case .pending: state = .pending
        case .running: state = .active
        case .completed: state = .completed
        case .skipped: state = .skipped
        case .failed: state = .failed
        }
        return SidebarProcessStepDisplay(
            id: progress.step.id,
            title: progress.step.title,
            detail: progress.detail,
            state: state,
            showsTransientStatus: false
        )
    }
}
