import SwiftUI
import Observation

/// A native presentation projection of the frontend's customFormTypes.ts JSON vocabulary.
/// The API field remains its generated opaque JSON container; unknown vocabulary fails closed.
@MainActor @Observable
final class MemberCustomForm {
    struct Question: Identifiable {
        let id: String
        let label: String
        let kind: String
        let required: Bool
        let options: [String]
    }
    let questions: [Question]
    let unavailable: Bool
    var text: [String: String] = [:]
    var multiple: [String: Set<String>] = [:]
    var errors: [String: String] = [:]
    init(data: Data?) {
        guard let data else { questions = []; unavailable = false; return }
        guard data.count <= 128_000, let raw = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { questions = []; unavailable = true; return }
        if raw is NSNull { questions = []; unavailable = false; return }
        guard let rows = raw as? [[String: Any]], rows.count <= 100 else { questions = []; unavailable = true; return }
        let known: Set<String> = ["short_text", "paragraph", "number", "date", "single_choice", "multi_choice", "dropdown", "yes_no"]
        var parsed: [Question] = []; var identifiers = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, id.count <= 200, identifiers.insert(id).inserted,
                  let label = row["label"] as? String, !label.isEmpty, label.count <= 1000,
                  let kind = row["type"] as? String, known.contains(kind), let required = row["required"] as? Bool,
                  let options = row["options"] as? [String], options.count <= 100, options.allSatisfy({ $0.count <= 1000 }) else {
                questions = []; unavailable = true; return
            }
            parsed.append(Question(id: id, label: label, kind: kind, required: required, options: options))
        }
        questions = parsed; unavailable = false
    }
    func validatedAnswers() -> [String: Any]? {
        errors = [:]
        guard !unavailable else { return nil }
        var values: [String: Any] = [:]
        for question in questions {
            let value = (text[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let choices = multiple[question.id] ?? []
            let empty = question.kind == "multi_choice" ? choices.isEmpty : value.isEmpty
            if empty { if question.required { errors[question.id] = String(localized: "This question is required.") }; continue }
            if question.kind == "multi_choice" {
                guard choices.isSubset(of: Set(question.options)) else { errors[question.id] = String(localized: "Choose one of the available options."); continue }
                values[question.id] = choices.sorted()
            } else if question.kind == "number" {
                let normalized = value.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
                guard normalized.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                      let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { errors[question.id] = String(localized: "Enter a valid number."); continue }
                let number = NSDecimalNumber(decimal: decimal)
                guard number.doubleValue.isFinite else { errors[question.id] = String(localized: "Enter a valid number."); continue }
                values[question.id] = number
            } else if question.kind == "date" {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
                formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
                guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil,
                      let date = formatter.date(from: value), formatter.string(from: date) == value else { errors[question.id] = String(localized: "Enter a date as YYYY-MM-DD."); continue }
                values[question.id] = value
            } else if question.kind == "yes_no" {
                guard ["true", "false"].contains(value) else { errors[question.id] = String(localized: "Choose Yes or No."); continue }
                values[question.id] = value == "true"
            } else if ["single_choice", "dropdown"].contains(question.kind) {
                guard question.options.contains(value) else { errors[question.id] = String(localized: "Choose one of the available options."); continue }
                values[question.id] = value
            } else { values[question.id] = value }
        }
        return errors.isEmpty ? values : nil
    }
}

struct MemberCustomFields: View {
    @Bindable var form: MemberCustomForm
    var body: some View {
        if form.unavailable {
            SWError(message: String(localized: "This form uses a question type the app doesn't support yet. Use the web console or ask your makerspace for help."))
        } else {
            ForEach(form.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.label + (question.required ? String(localized: " (required)") : "")).brandFont(.headline)
                    field(question)
                    if let error = form.errors[question.id] { Text(error).foregroundStyle(Color.swDanger) }
                }
            }
        }
    }
    private func binding(_ id: String) -> Binding<String> { Binding(get: { form.text[id] ?? "" }, set: { form.text[id] = $0; form.errors[id] = nil }) }
    @ViewBuilder private func field(_ question: MemberCustomForm.Question) -> some View {
        switch question.kind {
        case "yes_no":
            Picker(question.label, selection: binding(question.id)) { Text("Choose an option").tag(""); Text("Yes").tag("true"); Text("No").tag("false") }.frame(minHeight: 48)
        case "single_choice", "dropdown":
            Picker(question.label, selection: binding(question.id)) {
                Text("Choose an option").tag("")
                ForEach(Array(Set(question.options)).sorted(), id: \.self) { Text($0).tag($0) }
            }.frame(minHeight: 48)
        case "multi_choice":
            ForEach(Array(Set(question.options)).sorted(), id: \.self) { option in
                Button {
                    var choices = form.multiple[question.id] ?? []
                    if !choices.insert(option).inserted { choices.remove(option) }
                    form.multiple[question.id] = choices; form.errors[question.id] = nil
                } label: { Label(option, systemImage: form.multiple[question.id]?.contains(option) == true ? "checkmark.square.fill" : "square").frame(maxWidth: .infinity, minHeight: 48, alignment: .leading) }
                    .buttonStyle(.plain).accessibilityValue(form.multiple[question.id]?.contains(option) == true ? "Selected" : "Not selected")
            }
        case "date":
            MemberQuestionDate(title: question.label, value: binding(question.id))
        case "paragraph":
            TextField(question.label, text: binding(question.id), axis: .vertical).lineLimit(3...8).padding(12).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
        default:
            TextField(question.label, text: binding(question.id)).keyboardType(question.kind == "number" ? .numbersAndPunctuation : .default).frame(minHeight: 48)
                .padding(.horizontal, 12).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct MemberQuestionDate: View {
    let title: String
    @Binding var value: String
    @State private var date = Date()
    private var formatter: DateFormatter {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.calendar = Calendar(identifier: .gregorian)
        format.dateFormat = "yyyy-MM-dd"; format.isLenient = false; return format
    }
    var body: some View {
        Toggle("Choose a date for \(title)", isOn: Binding(get: { !value.isEmpty }, set: { value = $0 ? formatter.string(from: date) : "" })).frame(minHeight: 48)
        if !value.isEmpty {
            DatePicker(title, selection: Binding(get: { formatter.date(from: value) ?? date }, set: { date = $0; value = formatter.string(from: $0) }), displayedComponents: .date)
                .frame(minHeight: 48)
        }
    }
}
