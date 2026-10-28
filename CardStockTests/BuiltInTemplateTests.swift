import Foundation
import Testing
@testable import CardStock

@MainActor
struct BuiltInTemplateTests {
    @Test func templatesAreDistinctAndUseKnownFonts() throws {
        let all = BuiltInTemplate.all
        #expect(all.count == 6)
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map { try! JSONEncoder().encode($0.theme.look) }).count == all.count)
        for template in all {
            #expect(template.theme.look != ThemeSettings(), "\(template.name)")
            for id in template.theme.fontIDs {
                #expect(ThemeFont.named(id) != nil, "\(template.name): \(id)")
            }
        }
        // Some serif, some sans serif.
        let serif = all.filter { [.serif, .display].contains(ThemeFont.named($0.theme.bodyFont)?.category) || [.serif, .display].contains(ThemeFont.named($0.theme.headingFont)?.category) }
        #expect(serif.count == 3)
    }

    @Test func surviveSavingAndChoosing() throws {
        for template in BuiltInTemplate.all {
            let data = try JSONEncoder().encode(template.theme)
            #expect(try JSONDecoder().decode(ThemeSettings.self, from: data) == template.theme, "\(template.name)")
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "cardstock-templates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(styleLibrary: StyleLibrary(folder: dir.appending(path: "Styles")))
        model.createSite(at: dir.appending(path: "Site"))
        let studio = try #require(BuiltInTemplate.named("studio"))
        model.applyBuiltInTemplate(studio)
        #expect(model.currentStyleChoice == .builtIn("studio"))
        model.saveNow()
        model.reload()
        #expect(model.currentStyleChoice == .builtIn("studio"))
        model.applyDefaultStyle()
        #expect(model.currentStyleChoice == .builtInDefault)
    }
}
