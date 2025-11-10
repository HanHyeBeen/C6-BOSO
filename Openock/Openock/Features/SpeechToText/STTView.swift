import SwiftUI
import AVFoundation

struct STTView: View {
  @EnvironmentObject var pipeline: AudioPipeline
  @EnvironmentObject var settings: SettingsManager
  @State private var isExpanded = false

  private let lineSpacing: CGFloat = 4

  private func toggleWindowHeight() {
    guard let window = NSApp.keyWindow else { return }
    let current = window.frame
    let newHeight: CGFloat = isExpanded ? (current.height / 2) : (current.height * 2)
    let newFrame = NSRect(x: current.origin.x, y: current.origin.y, width: current.width, height: newHeight)
    window.setFrame(newFrame, display: true, animate: true)
    isExpanded.toggle()
  }

  var body: some View {
    ZStack {
      settings.backgroundColor
        .id(settings.selectedBackground)
        .glassEffect(.clear, in: .rect)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: settings.selectedBackground)

      VStack(spacing: 0) {
        // 상단 컨트롤 (녹음/일시정지)
        HStack {
          Spacer()
          if pipeline.isRecording {
            if pipeline.isPaused {
              Button(action: { pipeline.resumeRecording() }) {
                Image(systemName: "play.circle.fill").font(.system(size: 28))
              }
              .buttonStyle(.borderless).tint(.green)
            } else {
              Button(action: { pipeline.pauseRecording() }) {
                Image(systemName: "pause.circle.fill").font(.system(size: 28))
              }
              .buttonStyle(.borderless).tint(.orange)
            }
          }
        }
        .padding(.trailing, 10)
        .padding(.top, 10)

        // YAMNet 한 줄 상태
        Text(pipeline.yamStatus)
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity, alignment: .leading)

        // Transcript
        if pipeline.transcript.isEmpty {
          Spacer()
          VStack(alignment: .center, spacing: 10) {
            Image(systemName: "text.bubble")
              .font(.system(size: 40))
              .foregroundColor(.gray.opacity(0.5))
            Text("음성이 인식되면 여기에 표시됩니다...")
              .foregroundColor(.gray)
              .italic()
          }
          .frame(maxWidth: .infinity)
          .padding(.bottom, 20)
        } else {
          GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
              Spacer(minLength: 0)

              SubtitleFXView(
                text: pipeline.transcript,
                baseFontName: settings.selectedFont,
                baseFontSize: settings.fontSize,
                baseColor: settings.textColor,
                style: pipeline.fxStyle,   // LoudnessMeter → SubtitleFXEngine 결과
                lineSpacing: lineSpacing
              )
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
            .clipped()
          }
          .padding()
          .padding(.bottom, 20)
        }
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { toggleWindowHeight() }
    .onAppear { pipeline.startRecording() }
  }
}

#Preview {
  STTView()
    .environmentObject(AudioPipeline())
    .environmentObject(SettingsManager())
}
