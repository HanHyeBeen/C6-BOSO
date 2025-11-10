//
//  AudioPipeline.swift
//  Openock
//
//  Created by YONGWON SEO on 11/5/25.
//

import Foundation
import AVFoundation
import Combine

final class AudioPipeline: ObservableObject {
    // UI 상태
    @Published var yamStatus: String = "YAMNet: idle"
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false

    // 추가: 음압(dB)와 자막 스타일(폰트 크기/색/떨림)
    @Published var loudnessDB: Double = 0
    @Published var fxStyle: SubtitleStyle = .neutral

    // 내부 구성요소
    private let capture = AudioCaptureManager()
    private let io = AudioIOManager()
    private let yamRunner = YAMNetRunner()

    // 팀 공용 STT 엔진 사용 (분석 파이프라인만 사용)
    @available(macOS 15.0, *)
    private let sttEngine = STTEngine()

    // 추가: dB 측정 + 자막 스타일 엔진
    private let loudness = LoudnessMeter()
    private let fxEngine = SubtitleFXEngine()

    private var bag = Set<AnyCancellable>()

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

        // dB 측정값 구독 → 공개 상태 업데이트
        loudness.$dB
            .receive(on: DispatchQueue.main)
            .sink { [weak self] db in
                guard let self else { return }
                self.loudnessDB = db
                self.fxEngine.update(dB: db)
            }
            .store(in: &bag)

        // FX 스타일 구독 → 공개 상태 업데이트
        fxEngine.$style
            .receive(on: DispatchQueue.main)
            .assign(to: &$fxStyle)
    }

    // 캡처 + IO 시작
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
        io.isPaused = false
        isPaused = false
    }
}
