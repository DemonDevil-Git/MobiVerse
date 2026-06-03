import Testing
@testable import Mobi2EpubTransferCore

struct ConverterServiceTests {
    @Test
    func comicConversionCSSRemovesMarginsAndFixedImageSizing() {
        #expect(ConverterService.comicExtraCSS.contains("margin: 0 !important"))
        #expect(ConverterService.comicExtraCSS.contains("max-width: 100% !important"))
        #expect(ConverterService.comicExtraCSS.contains("max-height: 100vh !important"))
        #expect(ConverterService.comicExtraCSS.contains("@page"))
    }
}
