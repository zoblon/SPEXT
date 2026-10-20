import SwiftUI

/// The containing settings tab provides its section heading and scrolling.
struct ReplacementRulesView: View {
    @Binding var rules: [ReplacementRule]
    @State private var editingID: UUID?
    @State private var spoken = ""
    @State private var written = ""
    @FocusState private var spokenFocused: Bool

    private var candidate: ReplacementRule {
        ReplacementRule(id: editingID ?? UUID(), spoken: spoken, written: written)
    }

    private var validationIssue: ReplacementRules.ValidationIssue? {
        ReplacementRules.validationIssue(for: candidate, among: rules, excludingID: editingID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replacements apply locally after transcription, before rewriting or insertion. Whole terms match regardless of case, with flexible spaces. Rewritten messages may change the wording again.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rules.isEmpty {
                Text("No replacement rules added yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 4) {
                    ForEach(rules) { rule in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: rule.spoken)
                                    .font(.system(size: 12, weight: .medium))
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Image(systemName: "arrow.right")
                                        .accessibilityHidden(true)
                                    Text(verbatim: rule.written)
                                        .textSelection(.enabled)
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                editingID = rule.id
                                spoken = rule.spoken
                                written = rule.written
                                spokenFocused = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .help("Edit")
                            .accessibilityLabel("Edit replacement rule")

                            Button {
                                rules.removeAll { $0.id == rule.id }
                                if editingID == rule.id { resetEditor() }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                            .accessibilityLabel("Remove replacement rule")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(SPEXTTheme.surface.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spoken form")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Spoken form", text: $spoken)
                        .focused($spokenFocused)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Written form")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Written form", text: $written)
                }
                HStack(spacing: 8) {
                    if editingID == nil {
                        Button("Add") { saveRule() }
                            .disabled(validationIssue != nil)
                    } else {
                        Button("Save") { saveRule() }
                            .disabled(validationIssue != nil)
                        Button("Cancel") { resetEditor() }
                    }
                    Spacer()
                }
                .buttonStyle(.bordered)

                if !spoken.isEmpty || !written.isEmpty || editingID != nil {
                    if let issue = validationIssue {
                        validationText(issue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .onSubmit { saveRule() }
        }
    }

    private func validationText(_ issue: ReplacementRules.ValidationIssue) -> Text {
        switch issue {
        case .emptySpoken: Text("Enter a spoken form.")
        case .emptyWritten: Text("Enter a written form. Replacements cannot be empty.")
        case .lineBreak: Text("Use a single line for each form.")
        case .duplicateSpoken: Text("A rule with this spoken form already exists.")
        }
    }

    private func saveRule() {
        guard validationIssue == nil else { return }
        let rule = candidate
        if let index = rules.firstIndex(where: { $0.id == editingID }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        resetEditor()
        spokenFocused = true
    }

    private func resetEditor() {
        editingID = nil
        spoken = ""
        written = ""
    }
}
