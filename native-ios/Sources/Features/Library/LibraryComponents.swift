import ImageIO
import SwiftUI
import UIKit

struct LibrarySidebar: View {
    let records: [StoredRecord]
    @Binding var scope: LibraryScope
    @Binding var expandedSubject: String?
    let compact: Bool
    let onScopeChanged: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if compact {
                    Color.clear.frame(height: 8)
                } else {
                    Text("学习库")
                        .font(AppTheme.pageTitleFont)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                Button {
                    scope = LibraryScope()
                    expandedSubject = nil
                    onScopeChanged()
                } label: {
                    sidebarRow(
                        title: "全部",
                        systemImage: "tray.full.fill",
                        color: AppTheme.accent,
                        count: records.filter { ["errors", "notes", "stickies"].contains($0.collection) }.count,
                        selected: scope.isAll,
                        showsArrow: false,
                        expanded: false
                    )
                }
                .buttonStyle(.plain)

                ForEach(SubjectDefinition.all) { subject in
                    subjectSection(subject)
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 24)
        }
        .background(AppTheme.secondaryBackground.opacity(0.72))
    }

    @ViewBuilder
    private func subjectSection(_ subject: SubjectDefinition) -> some View {
        let expanded = expandedSubject == subject.name
        let selected = scope.subject == subject.name && scope.module == nil

        Button {
            scope.subject = subject.name
            scope.module = nil
            if subject.isFlat {
                expandedSubject = nil
            } else {
                expandedSubject = expanded ? nil : subject.name
            }
            onScopeChanged()
        } label: {
            sidebarRow(
                title: subject.name,
                systemImage: subject.systemImage,
                color: subject.color,
                count: count(subject: subject.name),
                selected: selected,
                showsArrow: !subject.isFlat,
                expanded: expanded
            )
        }
        .buttonStyle(.plain)

        if expanded && !subject.isFlat {
            VStack(spacing: 1) {
                ForEach(subject.modules, id: \.self) { module in
                    Button {
                        scope = LibraryScope(subject: subject.name, module: module)
                        onScopeChanged()
                    } label: {
                        Group {
                            if compact {
                                VStack(spacing: 2) {
                                    Text(module)
                                        .font(.system(size: 11, weight: scope.subject == subject.name && scope.module == module ? .semibold : .regular))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                    let moduleCount = count(subject: subject.name, module: module)
                                    if moduleCount > 0 {
                                        Text("\(moduleCount)").font(.system(size: 8)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                HStack(spacing: 8) {
                                    Text(module)
                                        .font(.system(size: 12, weight: scope.subject == subject.name && scope.module == module ? .semibold : .regular))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    let moduleCount = count(subject: subject.name, module: module)
                                    if moduleCount > 0 {
                                        Text("\(moduleCount)")
                                            .font(AppTheme.auxiliaryFont.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, 42)
                                .padding(.trailing, 12)
                            }
                        }
                        .foregroundStyle(scope.subject == subject.name && scope.module == module ? AppTheme.accent : Color.primary)
                        .frame(height: compact ? 36 : 34)
                        .background(
                            scope.subject == subject.name && scope.module == module ? AppTheme.accent.opacity(0.09) : Color.white.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(scope.subject == subject.name && scope.module == module ? AppTheme.accent.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 0.7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(
        title: String,
        systemImage: String,
        color: Color,
        count: Int,
        selected: Bool,
        showsArrow: Bool,
        expanded: Bool
    ) -> some View {
        if compact {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? AppTheme.accent : color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if count > 0 {
                    Text("\(count)").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                if showsArrow {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? AppTheme.accent : Color.primary)
            .background(selected ? AppTheme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .foregroundStyle(selected ? AppTheme.accent : color)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(AppTheme.auxiliaryFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if showsArrow {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .foregroundStyle(selected ? AppTheme.accent : Color.primary)
            .background(selected ? AppTheme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
    }

    private func count(subject: String, module: String? = nil) -> Int {
        records.lazy.filter {
            ["errors", "notes", "stickies"].contains($0.collection)
                && $0.subject == subject
                && (module == nil || $0.module == module)
        }.count
    }
}

struct LibraryRecordCard: View {
    let snapshot: LibraryRecordSnapshot
    let kind: LibraryContentKind
    var hiddenTags: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if kind == .errors {
                HStack(spacing: 5) {
                    Label((snapshot.record.module?.isEmpty == false ? snapshot.record.module : snapshot.record.subject) ?? "未分类", systemImage: "square.grid.2x2")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let firstTag = visibleTags.first {
                    Text(firstTag)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.10), in: Capsule())
                } else if let status = snapshot.status, !status.isEmpty {
                    Text(status)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Spacer()
                if let date = snapshot.createdAt {
                    Text(date, format: .dateTime.month().day())
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(snapshot.title)
                .font(AppTheme.bodyFont)
                .foregroundStyle(.primary)
                .lineLimit(kind == .errors ? 5 : 3)

            if !snapshot.summary.isEmpty && snapshot.summary != snapshot.title {
                Text(snapshot.summary)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if visibleTags.count > 1 {
                Text(visibleTags.dropFirst().joined(separator: " · "))
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
        }
    }

    private var visibleTags: [String] {
        snapshot.tags.filter { !hiddenTags.contains($0) }
    }

    private var tint: Color {
        switch kind {
        case .errors: AppTheme.danger
        case .notes: AppTheme.accent
        case .stickies: .orange
        case .words: .purple
        }
    }

    private var cardBackground: Color {
        guard kind == .stickies, let value = snapshot.colorHex else { return AppTheme.secondaryBackground }
        return Color(homeHex: value).opacity(0.26)
    }
}

private struct LibraryErrorRecordCard: View {
    let snapshot: LibraryRecordSnapshot
    let size: LibraryCardSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            images

            Text(snapshot.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.primary)
                .lineSpacing(2.5)
                .lineLimit(size.questionLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !snapshot.comparisonWords.isEmpty {
                NativeTagFlow(spacing: 6) {
                    ForEach(Array(snapshot.comparisonWords.enumerated()), id: \.offset) { _, words in
                        tag(words, foreground: AppTheme.accent, background: AppTheme.accent.opacity(0.09), weight: .semibold)
                    }
                }
            }

            if !snapshot.knowledgePoints.isEmpty || !snapshot.errorCause.isEmpty {
                NativeTagFlow(spacing: 6) {
                    ForEach(Array(snapshot.knowledgePoints.prefix(4).enumerated()), id: \.offset) { _, point in
                        tag(point, foreground: .secondary, background: Color.primary.opacity(0.045))
                    }
                    if !snapshot.errorCause.isEmpty {
                        tag(snapshot.errorCause, foreground: AppTheme.accent, background: AppTheme.accent.opacity(0.09))
                    }
                }
            }

            if !snapshot.pitfall.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "lightbulb.min")
                        .font(.system(size: 10, weight: .regular))
                    Text(snapshot.pitfall)
                        .lineLimit(size == .small ? 2 : 3)
                }
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineSpacing(1.5)
            }

            if let createdAt = snapshot.createdAt {
                Text(Self.dateFormatter.string(from: createdAt))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
    }

    @ViewBuilder
    private var images: some View {
        if !snapshot.imageValues.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(snapshot.imageValues.prefix(3).enumerated()), id: \.offset) { index, source in
                    LibraryCardThumbnail(
                        source: source,
                        cacheKey: "\(snapshot.id)-\(index)-\(source.count)",
                        maximumHeight: size.imageMaximumHeight
                    )
                }
                if snapshot.imageValues.count > 3 {
                    Text("+\(snapshot.imageValues.count - 3) 张图片")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private func tag(
        _ value: String,
        foreground: Color,
        background: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(value)
            .font(.system(size: 11, weight: weight))
            .foregroundStyle(foreground)
            .lineLimit(2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct LibraryCardThumbnail: View {
    let source: String
    let cacheKey: String
    let maximumHeight: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(uiColor: .tertiarySystemGroupedBackground)
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: min(110, maximumHeight))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maximumHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .task(id: cacheKey) {
            image = await Self.thumbnail(from: source, cacheKey: cacheKey)
        }
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 80 * 1_024 * 1_024
        return cache
    }()

    private static func thumbnail(from source: String, cacheKey: String) async -> UIImage? {
        let key = NSString(string: cacheKey)
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            let encoded: String
            if let marker = source.range(of: "base64,") {
                encoded = String(source[marker.upperBound...])
            } else {
                encoded = source
            }
            guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
                  let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 900,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
        if let image {
            let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }
}

struct LibraryMasonryGrid: View {
    let records: [LibraryRecordSnapshot]
    let kind: LibraryContentKind
    let cardSize: LibraryCardSize
    let onOpen: (LibraryRecordSnapshot) -> Void
    let onDelete: (LibraryRecordSnapshot) -> Void
    var hiddenTags: Set<String> = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: 12) {
                    ForEach(column) { record in
                        cardLink(record)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func cardLink(_ record: LibraryRecordSnapshot) -> some View {
        Group {
            if kind == .stickies {
                LibrarySwipeDeleteCard(onDelete: { onDelete(record) }) {
                    openButton(record)
                }
            } else {
                openButton(record)
            }
        }
    }

    private func openButton(_ record: LibraryRecordSnapshot) -> some View {
        Button { onOpen(record) } label: {
            if kind == .errors {
                LibraryErrorRecordCard(snapshot: record, size: cardSize)
            } else {
                LibraryRecordCard(snapshot: record, kind: kind, hiddenTags: hiddenTags)
            }
        }
        .buttonStyle(LibraryCardPressStyle(animated: kind == .errors))
    }

    private var columns: [[LibraryRecordSnapshot]] {
        let count = max(1, cardSize.columnCount)
        var result = Array(repeating: [LibraryRecordSnapshot](), count: count)
        var heights = Array(repeating: CGFloat.zero, count: count)
        for record in records {
            let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            result[index].append(record)
            heights[index] += estimatedHeight(of: record)
        }
        return result
    }

    private func estimatedHeight(of record: LibraryRecordSnapshot) -> CGFloat {
        guard kind == .errors else { return 145 }
        let textLines = min(cardSize.questionLineLimit, max(1, Int(ceil(Double(record.title.count) / 24.0))))
        let imageHeight = record.imageValues.isEmpty
            ? CGFloat.zero
            : CGFloat(min(3, record.imageValues.count)) * (cardSize.imageMaximumHeight * 0.72 + 8)
        let tagRows = record.knowledgePoints.isEmpty && record.errorCause.isEmpty ? 0 : max(1, Int(ceil(Double(record.knowledgePoints.count + (record.errorCause.isEmpty ? 0 : 1)) / 2.0)))
        return 54 + CGFloat(textLines * 20) + imageHeight + CGFloat(tagRows * 27) + (record.pitfall.isEmpty ? 0 : 40)
    }
}

private struct LibraryCardPressStyle: ButtonStyle {
    let animated: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(animated && configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct LibrarySwipeDeleteCard<Content: View>: View {
    let onDelete: () -> Void
    let content: Content
    @State private var offset: CGFloat = 0

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.danger, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-66, value.translation.width))
                        }
                        .onEnded { value in
                            let shouldOpen = value.predictedEndTranslation.width < -34 || value.translation.width < -30
                            withAnimation(.spring(duration: 0.22, bounce: 0.05)) { offset = shouldOpen ? -66 : 0 }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}
