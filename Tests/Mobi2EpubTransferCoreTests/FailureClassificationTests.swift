import Testing
@testable import Mobi2EpubTransferCore

struct FailureClassificationTests {
    @Test
    func classifiesDRMProtectedFiles() {
        let log = "Error: This book is locked and protected by DRM."
        #expect(ConverterService.classifyFailure(log: log) == .drmProtected)
    }

    @Test
    func classifiesUnreadableInput() {
        let log = "InputFormatPlugin: not a valid MOBI file, bad magic."
        #expect(ConverterService.classifyFailure(log: log) == .inputUnreadable)
    }

    @Test
    func classifiesOutputPermissionErrors() {
        let log = "OSError: Permission denied while writing output"
        #expect(ConverterService.classifyFailure(log: log) == .outputPermissionDenied)
    }

    @Test
    func classifiesGenericConversionFailure() {
        let log = "Conversion failed during EPUB generation"
        #expect(ConverterService.classifyFailure(log: log) == .conversionFailed)
    }
}
