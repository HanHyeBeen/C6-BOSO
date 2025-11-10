import SwiftUI

/// Frozen(과거) + Live(진행중)로 분리해 과거 자막은 절대 변하지 않게 유지.
/// STT가 문장을 수정해도 커밋 경계 구간을 안전하게 Frozen으로 이동(부족분은 원문에서 보충).
struct SubtitleFXView: View {
    let text: String
    let baseFontName: String
    let baseFontSize: CGFloat
    let baseColor: Color
    let style: SubtitleStyle
    let lineSpacing: CGFloat

    // 상태
    @State private var frozen: AttributedString = .init("")     // 과거(불변)
    @State private var live: AttributedString   = .init("")     // 현재 진행 중
    @State private var lastFullText: String     = ""            // 직전 전체 원문
    @State private var lastBoundaryCount: Int   = 0             // 직전 확정 경계(문자 수)

    var body: some View {
        let composed = frozen + live
        return Text(composed)
            .textSelection(.enabled)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { apply(newText: text) }
            .onChange(of: text) { apply(newText: $0) }
    }
}

// MARK: - 내부 로직
private extension SubtitleFXView {

    /// 줄바꿈/종결부호 기준으로 "확정 경계"를 잡는다. (경계문자 포함)
    func commitBoundaryCount(_ s: String) -> Int {
        let delimiters: [Character] = ["\n", ".", "?", "!", "…", "。"]
        var idx: Int = -1
        for (i, ch) in s.enumerated() where delimiters.contains(ch) { idx = i }
        return (idx >= 0) ? (idx + 1) : 0
    }

    func lcpCount(_ a: String, _ b: String) -> Int {
        let ac = Array(a), bc = Array(b)
        let n = min(ac.count, bc.count)
        var i = 0; while i < n, ac[i] == bc[i] { i += 1 }
        return i
    }

    func dropPrefix(_ asVal: inout AttributedString, chars: Int) -> AttributedString {
        guard chars > 0, asVal.characters.count > 0 else { return .init("") }
        let take = min(chars, asVal.characters.count)
        let s = asVal.startIndex
        let mid = asVal.index(s, offsetByCharacters: take)
        let prefix = AttributedString(asVal[s..<mid])
        asVal = AttributedString(asVal[mid..<asVal.endIndex])
        return prefix
    }

    func dropTail(_ asVal: inout AttributedString, dropCount: Int) {
        guard dropCount > 0 else { return }
        let total = asVal.characters.count
        let keep = max(0, total - dropCount)
        let s = asVal.startIndex
        let cut = asVal.index(s, offsetByCharacters: keep)
        asVal = AttributedString(asVal[s..<cut])
    }

    func makeAttributed(_ s: String, extra: CGFloat, color: Color?) -> AttributedString {
        var a = AttributedString(s)
        var c = AttributeContainer()
        c.font = .custom(baseFontName, size: baseFontSize + extra)
        c.foregroundColor = (color ?? baseColor)           // 검정 또는 노랑만
        if extra >= 8 { c.inlinePresentationIntent = .stronglyEmphasized }
        a.setAttributes(c)
        return a
    }

    func apply(newText: String) {
        // 1) 이번 업데이트의 확정 경계 (경계문자 포함)
        let newBoundary = commitBoundaryCount(newText)
        let delta = max(0, newBoundary - lastBoundaryCount)

        // 2) 경계가 전진했다면: live에서 먼저 가능한 만큼 잘라 frozen으로 이동
        if delta > 0 {
            // (a) live에서 가져갈 수 있는 만큼
            let movedFromLive = dropPrefix(&live, chars: delta)
            var committed = movedFromLive

            // (b) live에 없던 부족분은 원문에서 정확히 보충 (사라짐 방지)
            let movedCount = movedFromLive.characters.count
            if movedCount < delta {
                // 원문 substring: [lastBoundaryCount, newBoundary)
                let startIdx = newText.index(newText.startIndex, offsetBy: lastBoundaryCount)
                let endIdx   = newText.index(newText.startIndex, offsetBy: newBoundary)
                let fullSlice = String(newText[startIdx..<endIdx])

                // 이미 live에서 옮긴 부분(movedCount)을 제외한 나머지
                let remainingText = String(fullSlice.dropFirst(movedCount))
                if !remainingText.isEmpty {
                    committed.append( makeAttributed(remainingText,
                                                     extra: style.extraSize,
                                                     color: style.color) )
                }
            }
            frozen.append(committed)
        }

        // 3) Live 갱신 (경계 이후의 원문을 기준으로 diff)
        let newLiveText = String(newText.dropFirst(newBoundary))
        let curLiveText = String(live.characters)

        if newLiveText != curLiveText {
            let keep = lcpCount(curLiveText, newLiveText)
            let oldSuffix = curLiveText.count - keep
            dropTail(&live, dropCount: oldSuffix)

            let inc = String(newLiveText.dropFirst(keep))
            if !inc.isEmpty {
                live.append(makeAttributed(inc, extra: style.extraSize, color: style.color))
            }
        }

        // 4) 상태 저장
        lastBoundaryCount = newBoundary
        lastFullText = newText
    }
}
