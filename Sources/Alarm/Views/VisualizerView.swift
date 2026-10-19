import SwiftUI

public struct VisualizerView: View {
    @ObservedObject var audioEngine = AudioEngine.shared
    var barColor: Color = Color.red
    
    public init(barColor: Color = Color.red) {
        self.barColor = barColor
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<audioEngine.spectrumLevels.count, id: \.self) { index in
                let level = audioEngine.spectrumLevels[index]
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [
                                barColor.opacity(0.3),
                                barColor,
                                Color.white.opacity(0.8)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 8, height: max(6, level * 75))
                    .animation(.spring(response: 0.15, dampingFraction: 0.5), value: level)
            }
        }
        .frame(height: 80)
    }
}
