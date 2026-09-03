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
    let record: StoredRecord
    let session: LibraryInlineNoteSession
    @State private var editing = false
    @State private var draft = ""
    @State private var saved = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var displayHeight: CGFloat = 42

    private var storedNote: String {
        let object = record.jsonObject ?? [:]
        // An explicitly empty canonical field must not fall back to stale imported text.
        if let note = object["note"] as? String { return note }
        return ["content", "errorNote", "analysis"].compactMap { object[$0] as? String }.first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("错题笔记", systemImage: "note.text")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if editing { Button("完成") { finishEditing() }.font(.system(size: 12)) }
            }
            if editing {
                NativeRichTextEditor(html: $draft, minHeight: displayHeight, documentStyle: true, focusOnAppear: true)
            } else {
                noteDisplay
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft = storedNote
                        saved = draft
                        editing = true
                    }
            }
            if let errorMessage {
                Button("\(errorMessage) · 点击重试") { save() }
                    .font(.system(size: 11)).foregroundStyle(AppTheme.danger)
            }
        }
        .onAppear { session.finishEditing = finishEditing }
        .onChange(of: draft) { _, _ in
            guard editing else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                save()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
        .onDisappear {
            saveTask?.cancel()
            save()
            session.finishEditing = nil
        }
    }

    @ViewBuilder private var noteDisplay: some View {
        if storedNote.isEmpty {
            Text("点击添加错题笔记").font(.system(size: 13)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
        } else {
            NativeRichTextDisplay(html: storedNote, minHeight: 42)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { displayHeight = max(42, proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, height in displayHeight = max(42, height) }
                })
        }
    }

    @discardableResult private func finishEditing() -> Bool {
        saveTask?.cancel()
        guard save() else { return false }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        editing = false
        return true
    }

    @discardableResult private func save() -> Bool {
        guard editing, draft != saved else { return true }
        do {
            var object = record.jsonObject ?? [:]
            object["note"] = draft
            if object["content"] != nil { object["content"] = draft }
            object["updatedAt"] = ISO8601DateFormatter().string(from: .now)
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.updatedAt = .now
            try modelContext.save()
            saved = draft
            errorMessage = nil
            return true
        } catch {
            errorMessage = "笔记未保存，请勿离开"
            return false
        }
    }
}
