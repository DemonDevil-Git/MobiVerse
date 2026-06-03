import Testing
@testable import Mobi2EpubTransferCore

struct EpubValidatorTests {
    @Test
    func validationExitZeroWithoutWarningsPasses() {
        #expect(EpubValidator.validationStatus(exitCode: 0, output: "No errors found") == .passed)
    }

    @Test
    func validationExitZeroWithWarningsWarns() {
        #expect(EpubValidator.validationStatus(exitCode: 0, output: "WARNING: unused resource") == .warnings)
    }

    @Test
    func validationNonZeroFails() {
        #expect(EpubValidator.validationStatus(exitCode: 1, output: "ERROR: missing item") == .failed)
    }
}
