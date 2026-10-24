import SwiftUI
import MessageUI
import SafariServices
import UniformTypeIdentifiers

struct LinkFileDocument: FileDocument {
    static var contentType: UTType { UTType(filenameExtension: "webloc") ?? .xml }
    static var readableContentTypes: [UTType] { [contentType] }
    var data: Data
    init(url: URL? = nil) { data = (try? PropertyListSerialization.data(fromPropertyList: ["URL": url?.absoluteString ?? ""], format: .xml, options: 0)) ?? Data() }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct MessageComposer: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController(); controller.body = url.absoluteString; controller.messageComposeDelegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let finish: () -> Void
        init(finish: @escaping () -> Void) { self.finish = finish }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) { finish() }
    }
}

struct SafariScreen: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
