import Foundation
import Testing
@testable import SpectralLifter

@MainActor
struct ProcessingJobTests {
    @Test
    func progressMovesForwardWhenLogsArrive() {
        let job = ProcessingJob()
        let input = URL(fileURLWithPath: "/tmp/input.wav")

        job.prepareForSelection(input)
        job.beginProcessing()
        job.appendLog("入力音声を読み込みます")
        job.appendLog("音声を解析します")

        #expect(job.activeStep == .analyze)
        #expect(job.completedSteps.contains(.loadAudio))
        #expect(job.progressValue > 0)
    }

    @Test
    func successMarksAllStepsComplete() {
        let job = ProcessingJob()
        let output = URL(fileURLWithPath: "/tmp/output.wav")

        job.finishSuccess(output)

        #expect(job.progressValue == 1)
        #expect(job.completedSteps.count == ProcessingStep.allCases.count)
        #expect(job.activeStep == nil)
    }
}
