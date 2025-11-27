import SwiftUI

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {

    enum Mode { case scrollable, vstack }

    let mode: Mode
    let items: Data
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat
    let content: (Data.Element) -> Content

    init(
        mode: Mode = .vstack,
        items: Data,
        itemSpacing: CGFloat = 8,
        rowSpacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.mode = mode
        self.items = items
        self.itemSpacing = itemSpacing
        self.rowSpacing = rowSpacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            generateRows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generateRows() -> some View {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0
        let maxWidth = UIScreen.main.bounds.width - 60

        for item in items {
            let width = estimateWidth(content(item)) + itemSpacing
            if currentRowWidth + width > maxWidth {
                rows.append([item])
                currentRowWidth = width
            } else {
                rows[rows.count - 1].append(item)
                currentRowWidth += width
            }
        }

        return ForEach(0..<rows.count, id: \.self) { rowIndex in
            HStack(spacing: itemSpacing) {
                ForEach(rows[rowIndex], id: \.self) { item in
                    content(item)
                }
            }
        }
    }

    private func estimateWidth(_ view: Content) -> CGFloat {
        let controller = UIHostingController(rootView: view)
        controller.view.layoutIfNeeded()
        let size = controller.sizeThatFits(in: UIView.layoutFittingExpandedSize)
        return size.width
    }
}
