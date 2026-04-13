import SwiftUI

struct LocalBridgeTransientWorkspaceEditorView: View {
    let artifact: LocalBridgeTransientWorkspaceArtifact
    let onSave: (SnapshotEnvelope) -> Void
    let onExport: (SnapshotEnvelope) -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String
    @State private var validationMessage: String?

    init(
        snapshot: SnapshotEnvelope,
        artifact: LocalBridgeTransientWorkspaceArtifact,
        onSave: @escaping (SnapshotEnvelope) -> Void,
        onExport: @escaping (SnapshotEnvelope) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.artifact = artifact
        self.onSave = onSave
        self.onExport = onExport
        self.onDiscard = onDiscard
        _draftText = State(initialValue: Self.prettyPrintedJSON(for: snapshot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This editor works on an isolated transient snapshot workspace. Saving or exporting here does not mutate the live CloudKit-backed store.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(artifact.fileURL.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            TextEditor(text: $draftText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 420)

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Discard Workspace", role: .destructive) {
                    onDiscard()
                    dismiss()
                }

                Spacer()

                Button("Save Workspace") {
                    do {
                        onSave(try decodeDraft())
                        validationMessage = nil
                    } catch {
                        validationMessage = error.localizedDescription
                    }
                }

                Button("Export Signed Package") {
                    do {
                        let snapshot = try decodeDraft()
                        onExport(snapshot)
                        validationMessage = nil
                    } catch {
                        validationMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .navigationTitle("Bridge Workspace")
    }

    private func decodeDraft() throws -> SnapshotEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(SnapshotEnvelope.self, from: Data(draftText.utf8))
    }

    private static func prettyPrintedJSON(for snapshot: SnapshotEnvelope) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = (try? encoder.encode(snapshot)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
