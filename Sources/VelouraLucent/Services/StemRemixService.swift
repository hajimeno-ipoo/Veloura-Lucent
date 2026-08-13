import Foundation

enum StemRemixServiceError: LocalizedError, Equatable, Sendable {
    case missingRole(StemRole)
    case duplicateRole(StemRole)
    case unexpectedRole(StemRole)
    case invalidRunContract
    case invalidSignal(StemRole)
    case structuralMismatch(StemRole)
    case nonFiniteOutput

    var errorDescription: String? {
        switch self {
        case .missingRole(let role):
            "再ミックスに\(role.stemModeDisplayTitle)がありません。"
        case .duplicateRole(let role):
            "再ミックスに\(role.stemModeDisplayTitle)が重複しています。"
        case .unexpectedRole(let role):
            "再ミックスにrun契約外の\(role.stemModeDisplayTitle)があります。"
        case .invalidRunContract:
            "再ミックスの有効Stemと純粋加算順が一致しません。"
        case .invalidSignal(let role):
            "\(role.stemModeDisplayTitle)の音声構造またはサンプル値が不正です。"
        case .structuralMismatch(let role):
            "\(role.stemModeDisplayTitle)のsample rate、channel数、または長さが一致しません。"
        case .nonFiniteOutput:
            "再ミックス結果にNaNまたはInfinityが発生しました。"
        }
    }
}

struct StemRemixSignal: Sendable {
    let role: StemRole
    let raw: AudioSignal
    let corrected: AudioSignal
}

/// 補正済みStemの純粋加算とは分離された、本番用の再ミックス処理です。
///
/// 自動設定は今回のraw／補正済みStemからだけ算出し、固定ジャンル値や候補順位付けを
/// 使用しません。normalization、saturation、limitingは既存マスタリングへ委ねます。
struct StemRemixService: Sendable {
    func makeAutomaticPlan(
        stems: [StemRemixSignal],
        runContract: StemModelRunContract
    ) throws -> StemRemixAutomaticPlan {
        let roleOrder = try validatedRoleOrder(for: runContract)
        let accompanimentRoles = try accompanimentRoles(for: runContract)
        let signals = try validated(stems, roles: runContract.validationRoles)
        var settingsByRole: [StemRole: StemRemixRoleSettings] = [:]
        var gainEvidence: [StemRole: Float] = [:]
        var panEvidence: [StemRole: Float] = [:]
        var reverbEvidence: [StemRole: Float] = [:]

        for role in roleOrder {
            let pair = try required(role, in: signals)
            let rawLevel = activeProgramRMSDB(pair.raw)
            let correctedLevel = activeProgramRMSDB(pair.corrected)
            let levelDelta = finiteOrZero(rawLevel - correctedLevel)
            let gain = clamp(levelDelta, to: -6...6)

            let panMeasurement = stablePanMeasurement(
                raw: pair.raw,
                corrected: pair.corrected
            )

            let rawDecay = decayContinuity(pair.raw)
            let correctedDecay = decayContinuity(pair.corrected)
            let rawSpace = stereoSideRatio(pair.raw)
            let correctedSpace = stereoSideRatio(pair.corrected)
            let decayLoss = max(0, rawDecay - correctedDecay)
            let spaceLoss = max(0, rawSpace - correctedSpace)
            let reverbLoss = clamp(
                Float(decayLoss * 0.7 + spaceLoss * 0.3),
                to: 0...1
            )

            gainEvidence[role] = levelDelta
            panEvidence[role] = panMeasurement.evidence
            reverbEvidence[role] = reverbLoss
            settingsByRole[role] = StemRemixRoleSettings(
                gainDB: gain,
                pan: panMeasurement.automaticPan,
                reverbSend: clamp(reverbLoss * 0.45, to: 0...0.35)
            )
        }

        let drumsBassCollision = try collisionScore(
            trigger: required(.drums, in: signals).corrected,
            target: required(.bass, in: signals).corrected,
            lower: 35,
            upper: 180
        )
        let accompanimentBus = try combinedSignal(
            roles: accompanimentRoles,
            signals: signals.mapValues(\.corrected)
        )
        let vocalsAccompanimentCollision = try collisionScore(
            trigger: required(.vocals, in: signals).corrected,
            target: accompanimentBus,
            lower: 1_500,
            upper: 5_500,
            mismatchRole: .other
        )

        let maximumReverbLoss = reverbEvidence.values.max() ?? 0
        let rawSignals = try roleOrder.map { try required($0, in: signals).raw }
        let estimatedDecay = estimatedDecaySeconds(signals: rawSignals)
        let drumsToBassAmount = maskingAmount(from: drumsBassCollision)
        let vocalsToAccompanimentAmount = maskingAmount(
            from: vocalsAccompanimentCollision
        )
        let settings = StemRemixSettings(
            roleValues: settingsByRole,
            masking: StemRemixMaskingSettings(
                drumsToBassEnabled: drumsToBassAmount > 0,
                drumsToBassAmount: drumsToBassAmount,
                vocalsToAccompanimentEnabled: vocalsToAccompanimentAmount > 0,
                vocalsToAccompanimentAmount: vocalsToAccompanimentAmount
            ),
            reverbReturnLevel: clamp(maximumReverbLoss * 0.4, to: 0...0.3),
            reverbDecaySeconds: estimatedDecay
        )
        return StemRemixAutomaticPlan(
            settings: settings,
            gainEvidenceDB: gainEvidence,
            panEvidence: panEvidence,
            reverbLossEvidence: reverbEvidence,
            drumsBassCollision: drumsBassCollision,
            vocalsAccompanimentCollision: vocalsAccompanimentCollision
        )
    }

    func render(
        stems: [StemRemixSignal],
        settings: StemRemixSettings,
        runContract: StemModelRunContract,
        progressHandler: @escaping @Sendable (
            StemRemixRenderStage,
            StemRemixRenderStageState
        ) -> Void = { _, _ in }
    ) throws -> StemRemixRenderResult {
        let roleOrder = try validatedRoleOrder(for: runContract)
        let accompanimentRoles = try accompanimentRoles(for: runContract)
        let signals = try validated(stems, roles: runContract.validationRoles)
        var gainedByRole: [StemRole: AudioSignal] = [:]

        progressHandler(.gain, .running)
        for role in roleOrder {
            let signal = try required(role, in: signals).corrected
            let roleSettings = settings.settings(for: role)
            gainedByRole[role] = applyGain(signal, gainDB: roleSettings.gainDB)
        }
        progressHandler(.gain, .completed)

        progressHandler(.masking, .running)
        if settings.masking.drumsToBassEnabled,
           settings.masking.drumsToBassAmount > 0 {
            gainedByRole[.bass] = try applyDynamicMasking(
                trigger: requiredProcessed(.drums, in: gainedByRole),
                target: requiredProcessed(.bass, in: gainedByRole),
                lower: 35,
                upper: 180,
                amount: settings.masking.drumsToBassAmount
            )
        }
        if settings.masking.vocalsToAccompanimentEnabled,
           settings.masking.vocalsToAccompanimentAmount > 0 {
            let accompanimentBus = try combinedSignal(
                roles: accompanimentRoles,
                signals: gainedByRole
            )
            let sharedEnvelope = try dynamicMaskingEnvelope(
                trigger: requiredProcessed(.vocals, in: gainedByRole),
                target: accompanimentBus,
                lower: 1_500,
                upper: 5_500,
                mismatchRole: .other
            )
            for role in accompanimentRoles {
                gainedByRole[role] = applyMaskingEnvelope(
                    try requiredProcessed(role, in: gainedByRole),
                    lower: 1_500,
                    upper: 5_500,
                    amount: settings.masking.vocalsToAccompanimentAmount,
                    envelope: sharedEnvelope
                )
            }
        }
        progressHandler(.masking, .completed)

        progressHandler(.pan, .running)
        var processed: [StemRole: AudioSignal] = [:]
        for role in roleOrder {
            let gained = try requiredProcessed(role, in: gainedByRole)
            processed[role] = applyPan(
                gained,
                pan: settings.settings(for: role).pan
            )
        }
        progressHandler(.pan, .completed)

        progressHandler(.reverbSend, .running)
        let send = try sum(roleOrder.map { role in
            let signal = try requiredProcessed(role, in: processed)
            return applyLinearGain(
                signal,
                gain: settings.settings(for: role).reverbSend
            )
        })
        progressHandler(.reverbSend, .completed)

        progressHandler(.sharedReverb, .running)
        let reverb = sharedReverb(
            send,
            decaySeconds: settings.reverbDecaySeconds
        )
        let scaledReturn = applyLinearGain(
            reverb,
            gain: settings.reverbReturnLevel
        )
        progressHandler(.sharedReverb, .completed)

        progressHandler(.dryReturnMix, .running)
        let dry = try sum(roleOrder.map { try requiredProcessed($0, in: processed) })
        let remixed = try add(dry, scaledReturn)
        guard remixed.channels.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw StemRemixServiceError.nonFiniteOutput
        }
        progressHandler(.dryReturnMix, .completed)
        return StemRemixRenderResult(
            signal: remixed,
            drySignal: dry,
            reverbReturn: scaledReturn,
            appliedSettings: settings
        )
    }

    private func validated(
        _ stems: [StemRemixSignal],
        roles: [StemRole]
    ) throws -> [StemRole: StemRemixSignal] {
        var values: [StemRole: StemRemixSignal] = [:]
        let expectedRoles = Set(roles)
        for stem in stems {
            guard expectedRoles.contains(stem.role) else {
                throw StemRemixServiceError.unexpectedRole(stem.role)
            }
            guard values[stem.role] == nil else {
                throw StemRemixServiceError.duplicateRole(stem.role)
            }
            try validate(stem.raw, role: stem.role)
            try validate(stem.corrected, role: stem.role)
            guard structuresMatch(stem.raw, stem.corrected) else {
                throw StemRemixServiceError.structuralMismatch(stem.role)
            }
            values[stem.role] = stem
        }
        for role in roles where values[role] == nil {
            throw StemRemixServiceError.missingRole(role)
        }
        guard let referenceRole = roles.first else {
            throw StemRemixServiceError.invalidRunContract
        }
        let reference = try required(referenceRole, in: values).corrected
        for role in roles {
            guard structuresMatch(reference, try required(role, in: values).corrected) else {
                throw StemRemixServiceError.structuralMismatch(role)
            }
        }
        return values
    }

    private func validatedRoleOrder(
        for runContract: StemModelRunContract
    ) throws -> [StemRole] {
        let roles = runContract.validationRoles
        let order = runContract.pureSumOrder
        guard !roles.isEmpty,
              Set(roles).count == roles.count,
              Set(order).count == order.count,
              Set(runContract.activeRoles) == Set(roles),
              Set(order) == Set(roles),
              roles.contains(.drums),
              roles.contains(.bass),
              roles.contains(.vocals) else {
            throw StemRemixServiceError.invalidRunContract
        }
        return order
    }

    private func accompanimentRoles(
        for runContract: StemModelRunContract
    ) throws -> [StemRole] {
        let accompaniment = runContract.pureSumOrder.filter {
            $0 != .drums && $0 != .bass && $0 != .vocals
        }
        let expected: Set<StemRole> = switch runContract.separationModel {
        case .htdemucs:
            [.other]
        case .bsRoformerSW:
            [.other, .guitar, .piano]
        }
        guard Set(accompaniment) == expected else {
            throw StemRemixServiceError.invalidRunContract
        }
        return accompaniment
    }

    private func combinedSignal(
        roles: [StemRole],
        signals: [StemRole: AudioSignal]
    ) throws -> AudioSignal {
        let ordered = try roles.map { try requiredProcessed($0, in: signals) }
        guard ordered.count > 1 else {
            guard let only = ordered.first else {
                throw StemRemixServiceError.invalidRunContract
            }
            return only
        }
        return try sum(ordered)
    }

    private func validate(_ signal: AudioSignal, role: StemRole) throws {
        guard signal.sampleRate.isFinite,
              signal.sampleRate > 0,
              signal.channels.count == 2,
              signal.frameCount > 0,
              signal.channels.allSatisfy({
                  $0.count == signal.frameCount && !$0.contains(where: { !$0.isFinite })
              }) else {
            throw StemRemixServiceError.invalidSignal(role)
        }
    }

    private func required(
        _ role: StemRole,
        in signals: [StemRole: StemRemixSignal]
    ) throws -> StemRemixSignal {
        guard let signal = signals[role] else {
            throw StemRemixServiceError.missingRole(role)
        }
        return signal
    }

    private func requiredProcessed(
        _ role: StemRole,
        in signals: [StemRole: AudioSignal]
    ) throws -> AudioSignal {
        guard let signal = signals[role] else {
            throw StemRemixServiceError.missingRole(role)
        }
        return signal
    }

    private func structuresMatch(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channels.count == rhs.channels.count
            && lhs.frameCount == rhs.frameCount
            && lhs.channels.allSatisfy { $0.count == lhs.frameCount }
            && rhs.channels.allSatisfy { $0.count == rhs.frameCount }
    }

    private func activeProgramRMSDB(_ signal: AudioSignal) -> Float {
        let mono = signal.monoMixdown()
        let window = max(64, Int(signal.sampleRate * 0.02))
        let blockRMS = stride(from: 0, to: mono.count, by: window).map { start in
            let end = min(start + window, mono.count)
            guard end > start else { return 0.0 }
            let power = mono[start..<end].reduce(0.0) {
                $0 + Double($1) * Double($1)
            } / Double(end - start)
            return sqrt(max(power, 0))
        }
        guard let maximum = blockRMS.max(), maximum > 1e-9 else { return -120 }
        let distributionFloor = percentile(blockRMS, 40)
        let activityFloor = max(distributionFloor, maximum * 0.05)
        let active = blockRMS.filter { $0 > activityFloor }
        let values = active.isEmpty ? blockRMS : active
        let power = values.reduce(0.0) { $0 + $1 * $1 } / Double(values.count)
        return Float(20 * log10(max(sqrt(power), 1e-9)))
    }

    private func stablePanMeasurement(
        raw: AudioSignal,
        corrected: AudioSignal
    ) -> (evidence: Float, automaticPan: Float) {
        guard raw.channels.count == 2,
              corrected.channels.count == 2,
              structuresMatch(raw, corrected) else {
            return (0, 0)
        }

        let window = max(64, Int(raw.sampleRate * 0.02))
        var blocks: [(rawLevel: Double, correctedLevel: Double, delta: Double)] = []
        for start in stride(from: 0, to: raw.frameCount, by: window) {
            let end = min(start + window, raw.frameCount)
            guard end > start else { continue }
            let range = start..<end
            let rawLevel = stereoBlockRMS(raw, range: range)
            let correctedLevel = stereoBlockRMS(corrected, range: range)
            let rawCenter = stereoCenter(raw, range: range)
            let correctedCenter = stereoCenter(corrected, range: range)
            blocks.append((
                rawLevel: rawLevel,
                correctedLevel: correctedLevel,
                delta: rawCenter - correctedCenter
            ))
        }

        guard blocks.count >= 3 else { return (0, 0) }
        let rawLevels = blocks.map(\.rawLevel)
        let correctedLevels = blocks.map(\.correctedLevel)
        guard let rawMaximum = rawLevels.max(),
              let correctedMaximum = correctedLevels.max(),
              rawMaximum > 1e-9,
              correctedMaximum > 1e-9 else {
            return (0, 0)
        }
        let rawActivityFloor = max(percentile(rawLevels, 40), rawMaximum * 0.05)
        let correctedActivityFloor = max(
            percentile(correctedLevels, 40),
            correctedMaximum * 0.05
        )
        let activeDeltas = blocks.compactMap { block -> Double? in
            guard block.rawLevel >= rawActivityFloor,
                  block.correctedLevel >= correctedActivityFloor else {
                return nil
            }
            return block.delta
        }
        guard activeDeltas.count >= 3 else { return (0, 0) }

        let medianDelta = percentile(activeDeltas, 50)
        let evidence = Float(medianDelta)
        let lowerQuartile = percentile(activeDeltas, 25)
        let upperQuartile = percentile(activeDeltas, 75)
        let directionIsStable = lowerQuartile > 0 || upperQuartile < 0
        guard directionIsStable, abs(evidence) >= 0.005 else {
            return (evidence, 0)
        }
        return (evidence, clamp(evidence, to: -0.35...0.35))
    }

    private func stereoBlockRMS(
        _ signal: AudioSignal,
        range: Range<Int>
    ) -> Double {
        var power = 0.0
        for index in range {
            let left = Double(signal.channels[0][index])
            let right = Double(signal.channels[1][index])
            power += (left * left + right * right) * 0.5
        }
        return sqrt(power / Double(max(range.count, 1)))
    }

    private func stereoCenter(
        _ signal: AudioSignal,
        range: Range<Int>
    ) -> Double {
        var leftPower = 0.0
        var rightPower = 0.0
        for index in range {
            let left = Double(signal.channels[0][index])
            let right = Double(signal.channels[1][index])
            leftPower += left * left
            rightPower += right * right
        }
        let frameCount = Double(max(range.count, 1))
        let left = sqrt(leftPower / frameCount)
        let right = sqrt(rightPower / frameCount)
        return (right - left) / max(right + left, 1e-9)
    }

    private func stereoSideRatio(_ signal: AudioSignal) -> Double {
        guard signal.channels.count == 2 else { return 0 }
        var side = 0.0
        var mid = 0.0
        for index in signal.channels[0].indices {
            let left = Double(signal.channels[0][index])
            let right = Double(signal.channels[1][index])
            let midSample = (left + right) * 0.5
            let sideSample = (left - right) * 0.5
            mid += midSample * midSample
            side += sideSample * sideSample
        }
        return sqrt(side / max(mid, 1e-12))
    }

    private func decayContinuity(_ signal: AudioSignal) -> Double {
        let mono = signal.monoMixdown()
        let window = max(64, Int(signal.sampleRate * 0.02))
        let energies = stride(from: 0, to: mono.count, by: window).map { start in
            let end = min(start + window, mono.count)
            guard end > start else { return 0.0 }
            let sum = mono[start..<end].reduce(0.0) { $0 + Double($1 * $1) }
            return sqrt(sum / Double(end - start))
        }
        guard energies.count > 2 else { return 0 }
        let activityFloor = percentile(energies, 30)
        var weighted = 0.0
        var weight = 0.0
        for index in 1..<energies.count {
            let previous = energies[index - 1]
            let current = energies[index]
            guard previous > activityFloor, current < previous else { continue }
            let localWeight = previous
            weighted += min(current / max(previous, 1e-12), 1) * localWeight
            weight += localWeight
        }
        return weight > 0 ? weighted / weight : 0
    }

    private func estimatedDecaySeconds(signals: [AudioSignal]) -> Float {
        guard let reference = signals.first else { return 1 }
        let sumSignal = (try? sum(signals)) ?? reference
        let mono = sumSignal.monoMixdown()
        let window = max(64, Int(sumSignal.sampleRate * 0.02))
        let energies = stride(from: 0, to: mono.count, by: window).map { start in
            let end = min(start + window, mono.count)
            let sum = mono[start..<end].reduce(0.0) { $0 + Double($1 * $1) }
            return sqrt(sum / Double(max(end - start, 1)))
        }
        guard energies.count > 4 else { return 1 }
        let peak = percentile(energies, 90)
        let threshold = peak * 0.1
        var durations: [Double] = []
        for index in 1..<(energies.count - 1)
        where energies[index] >= peak && energies[index + 1] < energies[index] {
            var end = index + 1
            while end < energies.count, energies[end] > threshold {
                end += 1
            }
            if end > index + 1 {
                durations.append(Double(end - index) * Double(window) / sumSignal.sampleRate)
            }
        }
        guard !durations.isEmpty else { return 1 }
        return clamp(Float(percentile(durations, 50)), to: 0.25...4)
    }

    private func collisionScore(
        trigger: AudioSignal,
        target: AudioSignal,
        lower: Double,
        upper: Double,
        mismatchRole: StemRole = .drums
    ) throws -> Float {
        guard structuresMatch(trigger, target) else {
            throw StemRemixServiceError.structuralMismatch(mismatchRole)
        }
        let triggerBand = bandPass(trigger.monoMixdown(), lower: lower, upper: upper, sampleRate: trigger.sampleRate)
        let targetBand = bandPass(target.monoMixdown(), lower: lower, upper: upper, sampleRate: target.sampleRate)
        let triggerEnvelope = rmsEnvelope(triggerBand, sampleRate: trigger.sampleRate)
        let targetEnvelope = rmsEnvelope(targetBand, sampleRate: target.sampleRate)
        let triggerFloor = percentile(triggerEnvelope.map(Double.init), 60)
        let targetFloor = percentile(targetEnvelope.map(Double.init), 60)
        var overlap = 0.0
        var targetActivity = 0.0
        for index in triggerEnvelope.indices {
            let targetLevel = Double(targetEnvelope[index])
            guard targetLevel > targetFloor else { continue }
            targetActivity += targetLevel
            if Double(triggerEnvelope[index]) > triggerFloor {
                overlap += targetLevel
            }
        }
        return clamp(Float(overlap / max(targetActivity, 1e-12)), to: 0...1)
    }

    private func maskingAmount(from collision: Float) -> Float {
        let active = max(0, collision - 0.2) / 0.8
        return clamp(active * 0.35, to: 0...0.35)
    }

    private func applyGain(_ signal: AudioSignal, gainDB: Float) -> AudioSignal {
        applyLinearGain(signal, gain: powf(10, gainDB / 20))
    }

    private func applyLinearGain(_ signal: AudioSignal, gain: Float) -> AudioSignal {
        let safeGain = gain.isFinite ? max(0, gain) : 0
        return AudioSignal(
            channels: signal.channels.map { $0.map { $0 * safeGain } },
            sampleRate: signal.sampleRate
        )
    }

    private func applyPan(_ signal: AudioSignal, pan: Float) -> AudioSignal {
        guard signal.channels.count == 2 else { return signal }
        let value = clamp(pan, to: -1...1)
        let leftGain: Float = value > 0 ? cosf(value * .pi * 0.5) : 1
        let rightGain: Float = value < 0 ? cosf(-value * .pi * 0.5) : 1
        return AudioSignal(
            channels: [
                signal.channels[0].map { $0 * leftGain },
                signal.channels[1].map { $0 * rightGain },
            ],
            sampleRate: signal.sampleRate
        )
    }

    private func applyDynamicMasking(
        trigger: AudioSignal,
        target: AudioSignal,
        lower: Double,
        upper: Double,
        amount: Float
    ) throws -> AudioSignal {
        let envelope = try dynamicMaskingEnvelope(
            trigger: trigger,
            target: target,
            lower: lower,
            upper: upper,
            mismatchRole: .bass
        )
        return applyMaskingEnvelope(
            target,
            lower: lower,
            upper: upper,
            amount: amount,
            envelope: envelope
        )
    }

    private func dynamicMaskingEnvelope(
        trigger: AudioSignal,
        target: AudioSignal,
        lower: Double,
        upper: Double,
        mismatchRole: StemRole
    ) throws -> [Float] {
        guard structuresMatch(trigger, target) else {
            throw StemRemixServiceError.structuralMismatch(mismatchRole)
        }
        let triggerBand = bandPass(
            trigger.monoMixdown(),
            lower: lower,
            upper: upper,
            sampleRate: trigger.sampleRate
        )
        let targetBandMono = bandPass(
            target.monoMixdown(),
            lower: lower,
            upper: upper,
            sampleRate: target.sampleRate
        )
        let triggerEnvelope = rmsEnvelope(triggerBand, sampleRate: trigger.sampleRate)
        let targetEnvelope = rmsEnvelope(targetBandMono, sampleRate: target.sampleRate)
        let triggerFloor = Float(percentile(triggerEnvelope.map(Double.init), 55))
        let targetFloor = Float(percentile(targetEnvelope.map(Double.init), 45))
        let maximumTrigger = max(Float(percentile(triggerEnvelope.map(Double.init), 95)), triggerFloor + 1e-9)

        return triggerEnvelope.indices.map { index in
            guard triggerEnvelope[index] > triggerFloor,
                  targetEnvelope[index] > targetFloor else {
                return 0
            }
            return min(
                max(
                    (triggerEnvelope[index] - triggerFloor)
                        / max(maximumTrigger - triggerFloor, 1e-9),
                    0
                ),
                1
            )
        }
    }

    private func applyMaskingEnvelope(
        _ target: AudioSignal,
        lower: Double,
        upper: Double,
        amount: Float,
        envelope: [Float]
    ) -> AudioSignal {
        guard envelope.count == target.frameCount else { return target }
        let safeAmount = clamp(amount, to: 0...0.5)

        let channels = target.channels.map { channel in
            let targetBand = bandPass(
                channel,
                lower: lower,
                upper: upper,
                sampleRate: target.sampleRate
            )
            return channel.indices.map { index in
                channel[index] - targetBand[index] * safeAmount * envelope[index]
            }
        }
        return AudioSignal(channels: channels, sampleRate: target.sampleRate)
    }

    private func rmsEnvelope(_ samples: [Float], sampleRate: Double) -> [Float] {
        let attack = expf(-1 / max(Float(sampleRate) * 0.004, 1))
        let release = expf(-1 / max(Float(sampleRate) * 0.090, 1))
        var current: Float = 0
        return samples.map { sample in
            let power = sample * sample
            let coefficient = power > current ? attack : release
            current = coefficient * current + (1 - coefficient) * power
            return sqrtf(max(current, 0))
        }
    }

    private func sharedReverb(
        _ signal: AudioSignal,
        decaySeconds: Float
    ) -> AudioSignal {
        guard signal.channels.count == 2 else { return signal }
        let decay = clamp(decaySeconds, to: 0.25...4)
        let sampleRate = signal.sampleRate
        let combDelaysMs: [[Double]] = [
            [29.7, 37.1, 41.1, 43.7],
            [30.7, 36.1, 40.3, 44.9],
        ]
        let allPassDelaysMs: [[Double]] = [
            [5.0, 1.7],
            [5.3, 1.9],
        ]
        let diffuseChannels = signal.channels.indices.map { channelIndex in
            let input = signal.channels[channelIndex]
            var combSum = Array(repeating: Float.zero, count: input.count)
            for delayMs in combDelaysMs[channelIndex] {
                let delay = max(1, Int(sampleRate * delayMs / 1_000))
                let feedback = powf(
                    0.001,
                    Float(Double(delay) / sampleRate) / decay
                )
                let comb = feedbackComb(
                    input,
                    delaySamples: delay,
                    feedback: feedback,
                    damping: 0.35
                )
                for index in combSum.indices {
                    combSum[index] += comb[index] / Float(combDelaysMs[channelIndex].count)
                }
            }
            return allPassDelaysMs[channelIndex].reduce(combSum) { current, delayMs in
                allPassDiffuse(
                    current,
                    delaySamples: max(1, Int(sampleRate * delayMs / 1_000)),
                    feedback: 0.62
                )
            }
        }
        let crossfeed: Float = 0.12
        let channels = [
            diffuseChannels[0].indices.map { index in
                diffuseChannels[0][index] * (1 - crossfeed)
                    + diffuseChannels[1][index] * crossfeed
            },
            diffuseChannels[1].indices.map { index in
                diffuseChannels[1][index] * (1 - crossfeed)
                    + diffuseChannels[0][index] * crossfeed
            },
        ]
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func feedbackComb(
        _ input: [Float],
        delaySamples: Int,
        feedback: Float,
        damping: Float
    ) -> [Float] {
        let delay = max(delaySamples, 1)
        let safeFeedback = clamp(feedback, to: 0...0.999)
        let safeDamping = clamp(damping, to: 0...0.999)
        var line = Array(repeating: Float.zero, count: delay)
        var output = Array(repeating: Float.zero, count: input.count)
        var position = 0
        var damped: Float = 0
        for index in input.indices {
            let delayed = line[position]
            damped = damped * safeDamping + delayed * (1 - safeDamping)
            line[position] = input[index] + damped * safeFeedback
            output[index] = delayed
            position = (position + 1) % delay
        }
        return output
    }

    private func allPassDiffuse(
        _ input: [Float],
        delaySamples: Int,
        feedback: Float
    ) -> [Float] {
        let delay = max(delaySamples, 1)
        let safeFeedback = clamp(feedback, to: 0...0.999)
        var line = Array(repeating: Float.zero, count: delay)
        var output = Array(repeating: Float.zero, count: input.count)
        var position = 0
        for index in input.indices {
            let delayed = line[position]
            let diffused = delayed - input[index] * safeFeedback
            line[position] = input[index] + diffused * safeFeedback
            output[index] = diffused
            position = (position + 1) % delay
        }
        return output
    }

    private func sum(_ signals: [AudioSignal]) throws -> AudioSignal {
        guard let reference = signals.first else {
            throw StemRemixServiceError.missingRole(.drums)
        }
        var channels = Array(
            repeating: Array(repeating: Float.zero, count: reference.frameCount),
            count: reference.channels.count
        )
        for signal in signals {
            guard structuresMatch(reference, signal) else {
                throw StemRemixServiceError.structuralMismatch(.drums)
            }
            for channelIndex in channels.indices {
                for frameIndex in channels[channelIndex].indices {
                    channels[channelIndex][frameIndex] += signal.channels[channelIndex][frameIndex]
                }
            }
        }
        return AudioSignal(channels: channels, sampleRate: reference.sampleRate)
    }

    private func add(_ lhs: AudioSignal, _ rhs: AudioSignal) throws -> AudioSignal {
        guard structuresMatch(lhs, rhs) else {
            throw StemRemixServiceError.structuralMismatch(.drums)
        }
        return AudioSignal(
            channels: lhs.channels.indices.map { channelIndex in
                lhs.channels[channelIndex].indices.map { frameIndex in
                    lhs.channels[channelIndex][frameIndex]
                        + rhs.channels[channelIndex][frameIndex]
                }
            },
            sampleRate: lhs.sampleRate
        )
    }

    private func bandPass(
        _ samples: [Float],
        lower: Double,
        upper: Double,
        sampleRate: Double
    ) -> [Float] {
        let maximum = sampleRate * 0.5 - 100
        guard maximum > lower else { return Array(repeating: 0, count: samples.count) }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: lower, sampleRate: sampleRate),
            cutoff: min(upper, maximum),
            sampleRate: sampleRate
        )
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(
            max(Int(Double(sorted.count - 1) * percentile / 100), 0),
            sorted.count - 1
        )
        return sorted[position]
    }

    private func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value.isFinite ? value : 0, range.lowerBound), range.upperBound)
    }

    private func finiteOrZero(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
