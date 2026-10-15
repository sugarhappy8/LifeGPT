import LifeGPTCore
import SwiftUI

struct NewLifeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var gender = "Female"
    @State private var birthYear = 1985
    @State private var birthplace = ""
    @State private var currency = "USD"

    private let genders = ["Female", "Male", "Non-binary"]
    private let currencies = ["USD", "GBP", "EUR", "CAD", "AUD", "JPY", "INR"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A New Life").font(.title2.bold()).padding([.horizontal, .top], 20)
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Maya Thompson"))
                Picker("Gender", selection: $gender) {
                    ForEach(genders, id: \.self) { Text($0) }
                }
                Stepper(value: $birthYear, in: 1880...2080) {
                    LabeledContent("Birth year") { Text(String(birthYear)).monospacedDigit() }
                }
                TextField("Birthplace", text: $birthplace, prompt: Text("e.g. Chicago, USA"))
                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { Text($0) }
                }
                Text(EraGuide.notes(for: birthYear))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Button("Random") { randomize() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Be Born") {
                    let options = NewLifeOptions(
                        name: name.trimmingCharacters(in: .whitespaces),
                        gender: gender,
                        birthYear: birthYear,
                        birthplace: birthplace.trimmingCharacters(in: .whitespaces),
                        currency: currency
                    )
                    Task { await model.startLife(options) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || birthplace.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 460)
    }

    private func randomize() {
        let names = ["Maya Thompson", "Arthur Bell", "Lena Okafor", "Hiro Tanaka", "Rosa Delgado", "Sam Whitaker"]
        let places = [("Chicago, USA", "USD"), ("Manchester, England", "GBP"), ("Lyon, France", "EUR"),
                      ("Osaka, Japan", "JPY"), ("Toronto, Canada", "CAD"), ("Mumbai, India", "INR")]
        name = names.randomElement()!
        gender = genders.randomElement()!
        birthYear = Int.random(in: 1900...2010)
        let place = places.randomElement()!
        birthplace = place.0
        currency = place.1
    }
}
