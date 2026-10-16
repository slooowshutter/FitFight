import SwiftUI

/// Snake, to pass the wait while a character is drawn. Swipe to turn; edges wrap, so only your own tail ends a game.
/// `playing` lets the screen stop scrolling while a swipe steers the snake.
struct SnakeGame: View {
    @Binding var playing: Bool
    /// The highest score across all players, kept by the server.
    let record: Int
    /// A finished game's score and its playing time in milliseconds, for the server to keep.
    let onFinish: (_ score: Int, _ milliseconds: Int) -> Void
    @Environment(\.ffTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var snake: [Cell] = []
    @State private var direction = Cell(x: 1, y: 0)
    @State private var queued: Cell?
    @State private var food = Cell(x: 11, y: 7)
    @State private var over = false
    /// Time spent playing this game, pauses excluded; the server checks a score fits in it.
    @State private var elapsed = 0

    private struct Cell: Equatable { var x: Int; var y: Int }
    private let size = 15
    private var score: Int { max(0, snake.count - 3) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(String(appLocalized: "snake.score", defaultValue: "Score \(score)"))
                Spacer()
                Text(String(appLocalized: "snake.record", defaultValue: "Record \(max(record, score))"))
            }
            .ffType(.label).foregroundStyle(theme.textSecondary).monospacedDigit()
            Canvas { context, canvas in
                let cell = canvas.width / CGFloat(size)
                func rect(_ c: Cell) -> Path {
                    Path(roundedRect: CGRect(x: CGFloat(c.x) * cell + 1, y: CGFloat(c.y) * cell + 1, width: cell - 2, height: cell - 2),
                         cornerRadius: cell / 3)
                }
                if !snake.isEmpty { context.fill(rect(food), with: .color(theme.gold)) }
                for (index, part) in snake.enumerated() {
                    context.fill(rect(part), with: .color(index == 0 ? theme.mossText : theme.mossFill))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .background(theme.control, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .ffBorder(theme.hairline, radius: theme.radius.field)
            .overlay {
                if !playing {
                    Button(action: start) {
                        VStack(spacing: 6) {
                            Image(systemName: over ? "arrow.counterclockwise" : "play.fill").font(.system(size: 28, weight: .bold))
                            Text(over ? String(appLocalized: "Play again")
                                 : snake.isEmpty ? String(appLocalized: "Tap to play, swipe to turn")
                                 : String(appLocalized: "Tap to continue"))
                                .ffType(.label)
                        }
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
            }
            // Only during a game, so an idle board never blocks scrolling the sheet.
            .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
                let (dx, dy) = (drag.translation.width, drag.translation.height)
                let turn = abs(dx) > abs(dy) ? Cell(x: dx > 0 ? 1 : -1, y: 0) : Cell(x: 0, y: dy > 0 ? 1 : -1)
                // A snake cannot reverse into itself.
                if turn.x != -direction.x || turn.y != -direction.y { queued = turn }
            }, including: playing ? .all : .subviews)
            .sensoryFeedback(.impact(weight: .light), trigger: score)
            .sensoryFeedback(.error, trigger: over) { _, ended in ended }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(appLocalized: "Snake game"))
        }
        // The character screen scrolls the whole board into view before a game starts.
        .frame(maxWidth: 330)
        .frame(maxWidth: .infinity)
        .task(id: playing) {
            while playing, !Task.isCancelled {
                // A little faster per point, capped so it stays playable.
                let tick = max(80, 160 - score * 3)
                try? await Task.sleep(for: .milliseconds(tick))
                if playing {
                    elapsed += tick
                    step()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
        // Portraits finishing replace the board mid-game; the score still counts.
        .onDisappear {
            playing = false
            if !over, score > 0 {
                over = true
                onFinish(score, elapsed)
            }
        }
    }

    private func start() {
        if snake.isEmpty || over {
            snake = [Cell(x: 5, y: 7), Cell(x: 4, y: 7), Cell(x: 3, y: 7)]
            direction = Cell(x: 1, y: 0)
            queued = nil
            over = false
            elapsed = 0
            placeFood()
        }
        playing = true
    }

    private func step() {
        if let queued { direction = queued; self.queued = nil }
        guard let first = snake.first else { return }
        let head = Cell(x: (first.x + direction.x + size) % size, y: (first.y + direction.y + size) % size)
        let eats = head == food
        // The tail moves away this tick unless the snake grows, so stepping onto it is safe.
        if snake.dropLast(eats ? 0 : 1).contains(head) {
            over = true
            playing = false
            if score > 0 { onFinish(score, elapsed) }
            return
        }
        snake.insert(head, at: 0)
        if eats {
            placeFood()
        } else {
            snake.removeLast()
        }
    }

    private func placeFood() {
        var free: [Cell] = []
        for x in 0..<size { for y in 0..<size where !snake.contains(Cell(x: x, y: y)) { free.append(Cell(x: x, y: y)) } }
        if let cell = free.randomElement() { food = cell }
    }
}

/// The Snake record across all players.
struct SnakeRecord: Decodable {
    let record: Int
}
