import SwiftUI

struct ProjectToggleRow: View {
    let project: Project
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { onToggle($0) })) {
            Text(project.displayName)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
