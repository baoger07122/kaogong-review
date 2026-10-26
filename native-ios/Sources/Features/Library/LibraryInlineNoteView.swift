import SwiftData
import SwiftUI
import UIKit

/// The parent can finish editing before entering drawing mode without observing every keystroke.
final class LibraryInlineNoteSession: ObservableObject {
    var finishEditing: (() -> Bool)?
    func finish() -> Bool { finishEditing?() ?? true }
}

struct LibraryInlineNoteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    private let readNote: () -> String
    private let writeNote: (String, ModelContext) throws -> Void
    let session: LibraryInlineNoteSession
    let title: String
    @State private var editing = false
    @State private var draft = ""
    @State private var saved = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var displayWarning: String?

    private let noteCanvasMinimumHeight: CGFloat = 360

    init(record: StoredRecord, session: LibraryInlineNoteSession, title: String = "错题笔记") {
        self.session = session
        self.title = title
        readNote = {
            let object = record.jsonObject ?? [:]
            if let note = object["note"] as? String { return note }
            return ["content", "errorNote", "analysis"].compactMap { object[$0] as? String }.first ?? ""
        }
        writeNote = { draft, modelContext in
            var object = record.jsonObject ?? [:]
            object["note"] = draft
            object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.updatedAt = .now
            try modelContext.save()
        }
    }

    init(
        session: LibraryInlineNoteSession,
        title: String,
        readNote: @escaping () -> String,
        writeNote: @escaping (String, ModelContext) throws -> Void
    ) {
        self.session = session
        self.title = title
        self.readNote = readNote
        self.writeNote = writeNote
    }

    private var storedNote: String { readNote() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "note.text")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if editing {
                    Button("完成") { finishEditing() }
                        .font(.system(size: 12))
                        .accessibilityIdentifier("library-inline-note-finish")
                }
            }
            if editing {
                NativeRichTextEditor(
                    html: $draft,
                    minHeight: noteCanvasMinimumHeight,
                    documentStyle: true,
                    focusOnAppear: true
                )
                .accessibilityIdentifier("library-inline-note-editor")
                .padding(.horizontal, 8)
            } else {
                noteDisplay
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = storedNote
                        saved = draft
                        editing = true
                    }
            }
            if let errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试保存") { save() }
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
            } else if let displayWarning, !editing {
                Text(displayWarning)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { session.finishEditing = finishEditing }
        .onChange(of: draft) { _, _ in
            guard editing else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(1_400)) } catch { return }
                save()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
        .onDisappear {
            saveTask?.cancel()
            if editing { _ = finishEditing() }
            session.finishEditing = nil
        }
    }

    @ViewBuilder private var noteDisplay: some View {
        if storedNote.isEmpty {
            Text("点击添加错题笔记")
                .font(AppTheme.noteBodyFont)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: noteCanvasMinimumHeight, alignment: .topLeading)
        } else {
            NativeRichTextDisplay(
                html: storedNote,
                minHeight: noteCanvasMinimumHeight,
                onFallback: { displayWarning = "富文本预览已降级，原笔记内容仍保留" }
            )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("library-inline-note-display")
        }
    }

    @discardableResult private func finishEditing() -> Bool {
        guard editing else { return true }
        saveTask?.cancel()
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard save() else { return false }
        // Avoid replacing the editor during the same synchronous call that saves
        // SwiftData and ends the UIKit first-responder session.
        Task { @MainActor in
            await Task.yield()
            editing = false
        }
        return true
    }

    @discardableResult private func save() -> Bool {
        guard editing, draft != saved else { return true }
        do {
            try writeNote(draft, modelContext)
            saved = draft
            errorMessage = nil
            return true
        } catch {
            errorMessage = "笔记未保存，原内容未更改：\(error.localizedDescription)"
            return false
        }
    }
}
