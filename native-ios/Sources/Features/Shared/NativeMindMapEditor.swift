import SwiftUI

private struct MindMapNode: Codable, Identifiable, Equatable {
    var id: UUID
    var parentID: UUID?
    var text: String
    var collapsed: Bool
}

private struct MindMapDocument: Codable, Equatable {
    var nodes: [MindMapNode]
    static var empty: MindMapDocument { .init(nodes: [.init(id: UUID(), parentID: nil, text: "中心主题", collapsed: false)]) }
    static func decode(_ value: String) -> MindMapDocument {
        guard let data = value.data(using: .utf8), let result = try? JSONDecoder().decode(Self.self, from: data), !result.nodes.isEmpty else { return .empty }
        return result
    }
    var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}

struct NativeMindMapEditor: View {
    @Binding private var encodedDocument: String
    @State private var document: MindMapDocument
    @State private var selectedID: UUID?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    init(encodedDocument: Binding<String>) {
        _encodedDocument = encodedDocument
        let value = MindMapDocument.decode(encodedDocument.wrappedValue)
        _document = State(initialValue: value)
        _selectedID = State(initialValue: value.nodes.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { proxy in
                let positions = layout(in: proxy.size)
                ZStack {
                    Canvas { context, _ in
                        for node in visibleNodes {
                            guard let parentID = node.parentID, let start = positions[parentID], let end = positions[node.id] else { continue }
                            var path = Path(); path.move(to: CGPoint(x: start.x + 55, y: start.y)); path.addCurve(to: CGPoint(x: end.x - 55, y: end.y), control1: CGPoint(x: start.x + 95, y: start.y), control2: CGPoint(x: end.x - 95, y: end.y))
                            context.stroke(path, with: .color(AppTheme.accent.opacity(0.35)), lineWidth: 1.5)
                        }
                    }
                    ForEach(visibleNodes) { node in
                        Button { selectedID = node.id } label: {
                            VStack(spacing: 3) {
                                Text(node.text.isEmpty ? "未命名" : node.text).font(AppTheme.inputFont.weight(node.parentID == nil ? .semibold : .regular)).lineLimit(2)
                                if childCount(node.id) > 0 { Text(node.collapsed ? "+\(childCount(node.id))" : "\(childCount(node.id)) 个分支").font(.system(size: 9)).foregroundStyle(.secondary) }
                            }
                            .foregroundStyle(selectedID == node.id ? AppTheme.accent : .primary)
                            .frame(width: 110, minHeight: 48)
                            .background(selectedID == node.id ? AppTheme.accent.opacity(0.11) : AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedID == node.id ? AppTheme.accent.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .position(positions[node.id] ?? .zero)
                    }
                }
                .scaleEffect(zoom)
                .offset(pan)
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { pan = CGSize(width: lastPan.width + $0.translation.width, height: lastPan.height + $0.translation.height) }.onEnded { _ in lastPan = pan })
                .simultaneousGesture(MagnifyGesture().onChanged { zoom = min(2.2, max(0.55, lastZoom * $0.magnification)) }.onEnded { _ in lastZoom = zoom })
            }
            .frame(minHeight: 330)
            .background(Color.white)
            if selectedID != nil {
                Divider(); TextField("节点内容", text: selectedText).textFieldStyle(NativeTextFieldStyle()).padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius).stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
        .onChange(of: document) { _, value in encodedDocument = value.encoded }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                action("添加子节点", "plus") { addChild() }
                action("添加同级", "arrow.turn.down.right") { addSibling() }
                action("折叠", "rectangle.compress.vertical") { toggleCollapse() }
                action("删除", "trash") { removeSelected() }
                action("居中", "scope") { zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero }
            }.padding(8)
        }
    }

    private func action(_ title: String, _ image: String, handler: @escaping () -> Void) -> some View {
        Button(action: handler) { Label(title, systemImage: image).font(AppTheme.auxiliaryFont.weight(.semibold)).padding(.horizontal, 8).frame(height: 30).background(Color.primary.opacity(0.05), in: Capsule()) }.buttonStyle(.plain)
    }

    private var selectedText: Binding<String> {
        Binding(get: { document.nodes.first(where: { $0.id == selectedID })?.text ?? "" }, set: { value in if let index = document.nodes.firstIndex(where: { $0.id == selectedID }) { document.nodes[index].text = value } })
    }

    private var visibleNodes: [MindMapNode] {
        guard let root = document.nodes.first(where: { $0.parentID == nil }) else { return [] }
        var result: [MindMapNode] = []
        func append(_ node: MindMapNode) {
            result.append(node); guard !node.collapsed else { return }
            for child in document.nodes.filter({ $0.parentID == node.id }) { append(child) }
        }
        append(root); return result
    }

    private func layout(in size: CGSize) -> [UUID: CGPoint] {
        var depths: [UUID: Int] = [:]
        if let root = visibleNodes.first {
            depths[root.id] = 0
            var queue = [root]
            while !queue.isEmpty {
                let parent = queue.removeFirst(); let depth = depths[parent.id] ?? 0
                let children = visibleNodes.filter { $0.parentID == parent.id }
                for child in children { depths[child.id] = depth + 1; queue.append(child) }
            }
        }
        let grouped = Dictionary(grouping: visibleNodes) { depths[$0.id] ?? 0 }
        var positions: [UUID: CGPoint] = [:]
        for (depth, nodes) in grouped {
            let total = CGFloat(max(0, nodes.count - 1)) * 78
            for (index, node) in nodes.enumerated() {
                positions[node.id] = CGPoint(x: 80 + CGFloat(depth) * 165, y: size.height / 2 - total / 2 + CGFloat(index) * 78)
            }
        }
        return positions
    }

    private func childCount(_ id: UUID) -> Int { document.nodes.filter { $0.parentID == id }.count }
    private func addChild() { guard let parent = selectedID else { return }; let node = MindMapNode(id: UUID(), parentID: parent, text: "新节点", collapsed: false); document.nodes.append(node); selectedID = node.id }
    private func addSibling() { guard let selected = document.nodes.first(where: { $0.id == selectedID }), let parent = selected.parentID else { return }; let node = MindMapNode(id: UUID(), parentID: parent, text: "新节点", collapsed: false); document.nodes.append(node); selectedID = node.id }
    private func toggleCollapse() { if let index = document.nodes.firstIndex(where: { $0.id == selectedID }) { document.nodes[index].collapsed.toggle() } }
    private func removeSelected() {
        guard let id = selectedID, let node = document.nodes.first(where: { $0.id == id }), node.parentID != nil else { return }
        var removal = Set([id]); var changed = true
        while changed { changed = false; for item in document.nodes where item.parentID.map(removal.contains) == true && !removal.contains(item.id) { removal.insert(item.id); changed = true } }
        document.nodes.removeAll { removal.contains($0.id) }; selectedID = node.parentID
    }
}
