import SwiftUI
import AVFoundation

// 창 높이 조절 방지를 위한 Delegate
private final class WindowResizeDelegate: NSObject, NSWindowDelegate {
  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    // 높이는 현재 높이로 고정, 가로만 조절 가능
    return NSSize(width: frameSize.width, height: sender.frame.height)
  }
}

struct STTView: View {
  @EnvironmentObject var pipeline: AudioPipeline
  @EnvironmentObject var settings: SettingsManager
  @EnvironmentObject var appDelegate: AppDelegate
  @State private var window: NSWindow?
  @State private var showTextArea = true
  @State private var textHideTimer: Timer?
  @State private var isHovering = false
  @State private var lastHeightUpdate = Date.distantPast
  @State private var resizeDelegate = WindowResizeDelegate()
  @State private var titlebarColorView: NSView?
  @State private var hoverStateTimer: Timer?  // hover 상태 유지 타이머 (3초)

  private let lineSpacing: CGFloat = 4
  private let controlHeight: CGFloat = 50

  // 텍스트 2줄에 필요한 높이 계산 (폰트 크기에 따라 동적)
  private func baseTextAreaHeight() -> CGFloat {
    let fontName = settings.selectedFont
    let fontSize = CGFloat(settings.fontSize)
    let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)

    // 한 줄의 높이 = ascender - descender + leading
    let lineHeight = ceil(font.ascender - font.descender + font.leading)

    // 2줄 + 줄간격(lineSpacing 1번) + vertical padding(상하 12씩 총 24)
    let textHeight = (lineHeight * 2) + lineSpacing + 24

    return max(textHeight, 50) // 최소 높이 보장
  }

  // 전체 창 높이 계산 (콘텐츠 기준; 타이틀바는 항상 노출)
  private func totalWindowHeight() -> CGFloat {
    // 규칙에 따른 가시성 계산
    let controlsVisible = pipeline.isPaused || isHovering
    let textVisible = pipeline.isPaused ? showTextArea : true

    var height: CGFloat = 0

    if controlsVisible {
      height += controlHeight
    }
    if textVisible {
      height += baseTextAreaHeight()
    }

    // 둘 다 숨겨진 경우 콘텐츠 최소 높이 1 (타이틀바는 프레임에서 자동 포함)
    if !controlsVisible && !textVisible {
      height = 1
    }
    return height
  }

  // 창 높이 업데이트
  private func updateWindowHeight() {
    guard let w = window else {
      print("❌ updateWindowHeight: window is nil")
      return
    }

    // 원하는 콘텐츠 높이
    var desiredContentHeight = totalWindowHeight()
    desiredContentHeight = max(desiredContentHeight, 1)

    // 현재 프레임과 top 기준점 계산 (상단 고정)
    let currentFrame = w.frame
    let topY = currentFrame.maxY

    // 콘텐츠 높이를 프레임 높이로 변환
    let contentRect = NSRect(origin: .zero, size: NSSize(width: currentFrame.width, height: desiredContentHeight))
    let targetFrameForContent = w.frameRect(forContentRect: contentRect)
    let targetFrameHeight = targetFrameForContent.height

    // top 고정, 아래로만 늘이거나 줄이기
    let newOriginY = topY - targetFrameHeight
    let newFrame = NSRect(x: currentFrame.origin.x,
                          y: newOriginY,
                          width: currentFrame.width,
                          height: targetFrameHeight)

    print("📏 updateWindowHeight (content): desired=\(desiredContentHeight), frameHeight=\(targetFrameHeight)")

    // 콘텐츠 크기 제약 설정 (바운싱 방지)
    w.contentMinSize = NSSize(width: 200, height: 1)
    w.contentMaxSize = NSSize(width: 10000, height: 10000)

    // 현재 콘텐츠 폭을 유지한 채 콘텐츠 높이만 정확히 설정
    let currentContentRect = w.contentRect(forFrameRect: w.frame)
    let targetContentSize = NSSize(width: currentContentRect.width, height: desiredContentHeight)
    w.setContentSize(targetContentSize)

    // 사용자가 창 높이를 조절할 수 없도록 (폭은 자유, 높이는 고정)
    w.contentMinSize = NSSize(width: 200, height: desiredContentHeight)
    w.contentMaxSize = NSSize(width: 10000, height: desiredContentHeight)
  }

  private func throttledUpdateWindowHeight(minInterval: TimeInterval = 0.05) {
    let now = Date()
    if now.timeIntervalSince(lastHeightUpdate) >= minInterval {
      lastHeightUpdate = now
      updateWindowHeight()
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + minInterval) {
        updateWindowHeight()
        lastHeightUpdate = Date()
      }
    }
  }

  // 일시정지시 5초 후 텍스트 영역 숨김
  private func startTextHideTimer() {
    print("⏱️ startTextHideTimer called")
    textHideTimer?.invalidate()
    textHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
      print("⏰ Timer fired - hiding text area")
      print("   showTextArea before: \(self.showTextArea)")

      // 텍스트 영역 숨김 (애니메이션 없이 즉시)
      self.showTextArea = false
      print("   showTextArea after: \(self.showTextArea)")

      // 창 높이 즉시 갱신
      print("   Updating window height...")
      self.updateWindowHeight()
    }
  }

  var body: some View {
    let controlsVisible = pipeline.isPaused || isHovering
    let textVisible = pipeline.isPaused ? showTextArea : true

    ZStack(alignment: .top) {
      // 배경색을 가장 먼저 배치
      settings.backgroundColor
        .glassEffect(.clear, in: .rect)
        .ignoresSafeArea(.all)

      VStack(spacing: 0) {
          // 컨트롤 영역 (상단)
          if controlsVisible {
            HStack(alignment: .center, spacing: 0) {
              HStack {
                if pipeline.isPaused {
                  Text("일시정지")
                    .foregroundStyle(.primary)
                    .font(.system(size: 14, weight: .medium))
                }
              }
              .padding(.horizontal, 16)
              .frame(maxWidth: .infinity, alignment: .leading)

              HStack(alignment: .center, spacing: 8) {
                Button(action: {
                  if pipeline.isRecording {
                    pipeline.isPaused ? pipeline.resumeRecording() : pipeline.pauseRecording()
                  }
                }) {
                  Image(systemName: pipeline.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!pipeline.isRecording)
              }
              .padding(.trailing, 16)
            }
            .frame(height: controlHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(true)
            .zIndex(10)
          }

          // 텍스트 영역 (하단)
          if textVisible {
            Group {
              if pipeline.transcript.isEmpty {
                VStack(alignment: .center, spacing: 10) {
                  Image(systemName: "text.bubble")
                    .font(.system(size: 40))
                    .foregroundColor(.gray.opacity(0.5))
                  Text("음성이 인식되면 여기에 표시됩니다...")
                    .foregroundColor(.gray)
                    .italic()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
              } else {
                GeometryReader { geo in
                  VStack(alignment: .center, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(pipeline.transcript)
                      .font(Font.custom(settings.selectedFont, size: settings.fontSize))
                      .foregroundStyle(settings.textColor)
                      .lineSpacing(lineSpacing)
                      .multilineTextAlignment(.center)
                      .frame(maxWidth: .infinity)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                  .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                  .clipped()
                }
              }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: baseTextAreaHeight())
            .contentShape(Rectangle())
            .onTapGesture {
              updateWindowHeight()
            }
          }
      }
      .frame(maxWidth: .infinity)
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .onHover { hovering in
      if hovering {
        // 마우스가 들어옴 -> 즉시 hover 상태로 변경
        hoverStateTimer?.invalidate()  // 진행 중인 타이머 취소
        isHovering = true
        if !pipeline.isPaused {
          throttledUpdateWindowHeight()
        }
      } else {
        // 마우스가 벗어남 -> 3초 후 숨김
        hoverStateTimer?.invalidate()
        hoverStateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
          self.isHovering = false
          if !pipeline.isPaused {
            throttledUpdateWindowHeight()
          }
        }
      }
    }
    .onChange(of: appDelegate.windowDidBecomeKey) {
      if appDelegate.windowDidBecomeKey {
        throttledUpdateWindowHeight()
        DispatchQueue.main.async { appDelegate.windowDidBecomeKey = false }
      }
    }
    .onChange(of: pipeline.isPaused) { isPaused in
      if isPaused {
        // 일시정지: 컨트롤은 항상 보임, 텍스트는 5초 후 사라짐 (처음엔 보였다가 사라짐)
        textHideTimer?.invalidate()
        // 반드시 텍스트를 다시 보이게 한 뒤 타이머 시작
        if !showTextArea { showTextArea = true }
        startTextHideTimer()
        throttledUpdateWindowHeight()
      } else {
        // 재생 재개: 텍스트는 반드시 보이도록 복구, 컨트롤은 hover에 따라 표시
        textHideTimer?.invalidate()
        if !showTextArea {
          withAnimation(.easeInOut(duration: 0.3)) {
            showTextArea = true
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          throttledUpdateWindowHeight()
        }
      }
    }
    .onAppear {
      pipeline.startRecording()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        throttledUpdateWindowHeight()
      }
    }
    .onChange(of: settings.fontSize) { _ in
      throttledUpdateWindowHeight()
    }
    .onDisappear {
      textHideTimer?.invalidate()
      textHideTimer = nil
      hoverStateTimer?.invalidate()
      hoverStateTimer = nil
    }
    .background(
      WindowAccessor { win in
        self.window = win
        if let w = win {
          print("🪟 WindowAccessor: Setting up window")

          // Delegate 설정으로 높이 조절 방지
          w.delegate = resizeDelegate

          // Liquid Glass 효과 적용
          w.applyLiquidGlass()

          w.isMovableByWindowBackground = true
          w.toolbar = nil

          print("✅ Window setup complete - fullSizeContentView: \(w.styleMask.contains(.fullSizeContentView))")

          w.contentResizeIncrements = NSSize(width: 1, height: 1)
          w.contentMinSize = NSSize(width: 200, height: 1)
          w.contentMaxSize = NSSize(width: 10000, height: 10000)

          w.styleMask.insert(.resizable)
          w.resizeIncrements = NSSize(width: 1, height: 1)

          if let contentView = w.contentView {
            contentView.autoresizingMask = [.width]
            contentView.translatesAutoresizingMaskIntoConstraints = true
          }
        }
      }
    )
  }
}

struct WindowAccessor: NSViewRepresentable {
  var onResolve: (NSWindow?) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      onResolve(view.window)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
  }
}

#Preview {
  STTView()
    .environmentObject(AudioPipeline())
    .environmentObject(SettingsManager())
    .environmentObject(AppDelegate())
}
