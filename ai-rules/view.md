# SwiftUI View Performance

<primary_directive>
Compose SwiftUI views so that state changes only re-render the parts of the UI that actually need to update. Prioritize predictable diffing, focused view structs, and lightweight diagnostics when investigating performance.
</primary_directive>

## Core Practices

<rule_1 priority="high">
Break Up Expensive Bodies
- Move sizable sections of a view body into dedicated child view structs instead of computed properties returning `some View`; SwiftUI can then diff each child separately.
- Apply this when a view body grows beyond a couple of logical responsibilities or when profiling shows widespread recomputation.
- Pass only the data each child needs so that updates remain localized.

Example:
```swift
struct SearchScreen: View {
    let headerModel: HeaderModel
    let results: [ResultModel]
    let onSelect: (ResultModel) -> Void

    var body: some View {
        VStack(spacing: 16) {
            SearchHeader(model: headerModel)
            ResultsList(results: results, onSelect: onSelect)
        }
    }
}

struct SearchHeader: View, Equatable {
    let model: HeaderModel
    var body: some View { Text(model.title).font(.title2) }
}
```
</rule_1>

<rule_2 priority="high">
Keep Views Diffable
- Prefer value-semantic properties on your view structs; if you must store reference types or closures, gate re-renders by conforming the view to `Equatable` and comparing only the properties that influence the output.
- Exclude helper objects (such as handlers) from the comparison when they do not change the rendered result.
- Use this approach when you notice a view re-rendering despite its visible state remaining static.

Example:
```swift
struct ResultCard: View, Equatable {
    let model: ResultModel
    let isHighlighted: Bool
    let onTap: () -> Void // not part of diffing

    static func == (lhs: ResultCard, rhs: ResultCard) -> Bool {
        lhs.model == rhs.model && lhs.isHighlighted == rhs.isHighlighted
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(model.title)
            Text(model.subtitle)
        }
        .padding()
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : .clear)
        .onTapGesture(perform: onTap)
    }
}
```
</rule_2>

<rule_3 priority="medium">
Visualize Re-render Frequency
- When debugging view performance, add temporary debugging modifiers (for example, overlaying a random color or logging in `onAppear`) to confirm whether a view re-renders more often than expected.
- Use this technique during performance investigations to target the specific subview causing churn before refactoring.
- Remove the diagnostic code once the issue is addressed to keep production builds clean.

Example:
```swift
extension Color {
    static var debugRandom: Color {
        Color(hue: .random(in: 0...1), saturation: 0.5, brightness: 0.9)
    }
}

extension View {
    func debugRenderHighlight() -> some View {
        overlay(Color.debugRandom.opacity(0.12))
    }
}

ResultCard(...)
    .debugRenderHighlight() // flashes when the view re-renders
```
</rule_3>
