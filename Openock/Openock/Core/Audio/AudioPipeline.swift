//
//  AudioPipeline.swift
//  Openock
//
//  Created by YONGWON SEO on 11/5/25.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

final class AudioPipeline: ObservableObject {
    // MARK: - UI 상태
    @Published var yamStatus: String = "YAMNet: idle"
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false

    // MARK: - 라우드니스/스타일 공개 값
    @Published var loudnessDB: Double = 0
    @Published var fxStyle: SubtitleStyle = .neutral

    // MARK: - 내부 구성요소
    private let capture = AudioCaptureManager()
    private let io = AudioIOManager()
    private let yamRunner = YAMNetRunner()

    // 팀 공용 STT 엔진 사용 (분석 파이프라인만 사용)
    @available(macOS 15.0, *)
    private let sttEngine = STTEngine()

    // 라우드니스/스타일 엔진
    private let loudness = LoudnessMeter()
    private let fxEngine = SubtitleFXEngine()

    // MARK: - Settings (외부 주입)
    private var settings: SettingsManager?
    private var currentFontSize: CGFloat = 24
    private var currentTextColor: Color = .black
    private var currentBackgroundKey: String = "화이트" // 기본: 라이트 가정

    // MARK: - Combine
    private var bag = Set<AnyCancellable>()
    private var settingsBag = Set<AnyCancellable>()

    // MARK: - Init
    init() {
        // YAM 상태 반영
        yamRunner.$statusText
            .receive(on: DispatchQueue.main)
            .assign(to: &$yamStatus)

        // STTEngine의 transcript 반영
        if #available(macOS 15.0, *) {
            sttEngine.$transcript
                .receive(on: DispatchQueue.main)
                .assign(to: &$transcript)
        }

        // dB 측정값 구독 → fx 업데이트
        loudness.$dB
            .receive(on: DispatchQueue.main)
            .sink { [weak self] db in
                guard let self else { return }
                self.loudnessDB = db
                self.refreshFXStyle() // ← 항상 최신 settings 기준으로 계산
            }
            .store(in: &bag)

        // FX 스타일 구독 → 공개 상태 업데이트
        fxEngine.$style
            .receive(on: DispatchQueue.main)
            .assign(to: &$fxStyle)
    }

    // MARK: - Settings 바인딩 (STTView.onAppear에서 호출 권장)
    func bindSettings(_ settings: SettingsManager) {
        self.settings = settings
        settingsBag.removeAll()

        // 현재값 초기화
        currentFontSize = settings.fontSize
        currentTextColor = settings.textColor
        currentBackgroundKey = normalizeBackgroundKey(settings.selectedBackground)

        // 변경 구독
        settings.$fontSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                self?.currentFontSize = size
                self?.refreshFXStyle()
            }
            .store(in: &settingsBag)

        // textColor는 derived 프로퍼티라 publisher가 없으므로
        // selectedBackground와 custom 색 저장소 둘 다를 감시해서 갱신
        settings.$selectedBackground
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak settings] bg in
                guard let self, let settings else { return }
                self.currentBackgroundKey = self.normalizeBackgroundKey(bg)
                self.currentTextColor = settings.textColor
                self.refreshFXStyle()
            }
            .store(in: &settingsBag)

        // 커스텀 컬러 선택 시에도 textColor가 변하므로 ColorPicker 열림/닫힘에만 의존하지 말고
        // 주기적 동기화를 위해 약한 폴링 없이도 안전하게 `save()` 호출 지점이 많다고 가정.
        // 안전하게 250ms 디바운스로 색 변화를 추적할 수 있게 한 번 더 바인딩:
        // (SettingsManager의 computed textColor를 주기적으로 읽진 않음. selectedBackground가 '커스텀'일 때 유효)
        // 필요 없으면 아래 블록은 제거해도 무방.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self, weak settings] _ in
                guard let self, let settings else { return }
                // 커스텀 모드에서 색이 바뀐 뒤 save() 되었을 가능성 반영
                self.currentTextColor = settings.textColor
                self.refreshFXStyle()
            }
            .store(in: &settingsBag)

        // 바인딩 직후 한 번 계산
        refreshFXStyle()
    }

    // MARK: - FX 재계산 (항상 최신 dB + 최신 설정으로)
    private func refreshFXStyle() {
        fxEngine.update(
            dB: loudnessDB,
            baseFontSize: currentFontSize,
            baseTextColor: currentTextColor,
            selectedBackground: currentBackgroundKey
        )
        // fxEngine.$style → fxStyle로 이미 바인딩되어 있음
    }

    // "블랙/화이트/커스텀" 외 표현이 들어와도 유연히 처리
    private func normalizeBackgroundKey(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("custom") || lower.contains("커스텀") { return "커스텀" }
        if lower.contains("black")  || lower.contains("블랙")   { return "블랙" }
        if lower.contains("white")  || lower.contains("화이트") { return "화이트" }
        // 기본은 라이트로 가정
        return "화이트"
    }

    // MARK: - 캡처 + IO
    func setupAndStart() {
        capture.setupFullSystemCapture { [weak self] deviceID in
            guard let self, let devID = deviceID else { return }

            // STTEngine: 캡처/IO는 쓰지 않고, 분석 파이프라인만 켜기
            if #available(macOS 15.0, *) {
                Task { @MainActor in
                    await self.sttEngine.startTranscriptionOnly()
                }
            }

            let ok = self.io.startIO(
                deviceID: devID,
                bufferCallback: { [weak self] pcm in
                    guard let self else { return }
                    // 1) YAMNet (러너가 내부에서 16k 변환)
                    self.yamRunner.ingest(pcm)
                    // 2) STT (원본 PCM 그대로 전달)
                    if #available(macOS 15.0, *) {
                        self.sttEngine.feed(buffer: pcm)
                    }
                    // 3) dB 측정 (원본 PCM 사용)
                    self.loudness.ingest(pcm)
                },
                levelCallback: { _ in }
            )

            DispatchQueue.main.async {
                self.isRecording = ok
                self.isPaused = false
            }
        }
    }

    // MARK: - Public controls
    func startRecording() { // 뷰에서 호출
        setupAndStart()
    }

    func stop() {
        io.stopIO()
        capture.cleanup()
        if #available(macOS 15.0, *) {
            sttEngine.stopTranscriptionOnly() // 전사 파이프라인만 정리
        }
        isRecording = false
        isPaused = false
    }

    func pauseRecording() {
        io.isPaused = true
        isPaused = true
    }

    func resumeRecording() {
        // 재개 시 STT 파이프라인 완전히 재시작
        if #available(macOS 15.0, *) {
            // 기존 파이프라인 정지
            sttEngine.stopTranscriptionOnly()
            // 텍스트 초기화
            sttEngine.clearTranscript()
            // 파이프라인 재시작
            Task { @MainActor in
                await sttEngine.startTranscriptionOnly()
            }
        }

        io.isPaused = false
        isPaused = false
        transcript = ""
    }
}
