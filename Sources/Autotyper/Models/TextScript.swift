import Foundation

/// Top-level pre-typing representation. The pipeline is:
///   text → SynonymDweller.split → [TextScript]
///   [TextScript] → TypoInjector.toLogicalKeys → [LogicalKey]
///   [LogicalKey] → Planner.planFromStream → [KeyEvent]
///
/// `.dwell` blocks bypass typo injection because the second-guessing motion is
/// itself a deliberate error-then-correction; piling typos on top would over-noise
/// the output. They participate in normal IKI/dwell timing in the planner.
enum TextScript {
    case run(String)
    /// Type `typed`, pause briefly (handled by planner via extraDelayMs), backspace,
    /// then type `then`.
    case dwell(typed: String, then: String)
}
