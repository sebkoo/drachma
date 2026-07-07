import SwiftUI

/// A searchable currency chooser — at 340 currencies a wheel is unusable, so
/// this searches the code and the localized name ("vietnam" finds VND).
struct CurrencySelectorView: View {
    let title: String
    let options: [CurrencyOption]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(ConverterViewModel.filter(options, query: query)) { option in
                Button {
                    onSelect(option.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(option.code)
                            .fontWeight(.semibold)
                            .frame(width: 64, alignment: .leading)
                        Text(option.name)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Search currency or country")
            .navigationTitle(title)
        }
    }
}
