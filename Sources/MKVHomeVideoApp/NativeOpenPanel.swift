import AppKit
import UniformTypeIdentifiers

@MainActor
enum NativeOpenPanel {
    static func chooseFiles(
        contentTypes: [UTType],
        allowsMultipleSelection: Bool,
        message: String,
        prompt: String
    ) -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = contentTypes
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : nil
    }

    static func chooseDirectory(message: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
