import SwiftUI

struct TermHelpButton: View {
    let title: String
    let reading: String
    let description: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)の説明")
        .help("\(title)の説明を表示します")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(reading)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 360, alignment: .leading)
        }
    }
}
