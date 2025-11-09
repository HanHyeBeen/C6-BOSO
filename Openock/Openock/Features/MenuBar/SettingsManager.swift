//
//  SettingsManager.swift
//  Openock
//
//  Created by Enoch on 11/1/25.
//

import SwiftUI
import Combine

final class SettingsManager: ObservableObject {
  // MARK: - Appearance
  @Published var selectedFont: String = "SF Pro"
  @Published var fontSize: CGFloat = 24
  @Published var selectedBackground: String = "black"
  
  // MARK: - Sound
  @Published var isSoundEnabled: Bool = true
  
  // MARK: - Shortcut
  @Published var isShortcutEnabled: Bool = true
  
  // MARK: - Derived color properties
  var backgroundColor: Color {
    switch selectedBackground {
    case "블랙", "black": return .black
    case "화이트", "white": return .white
    case "투명", "clear": return .clear
    case "커스텀", "custom": return Color.pink.opacity(0.2)
    default: return .black  // 기본값을 블랙으로 변경
    }
  }

  var textColor: Color {
    switch selectedBackground {
    case "블랙", "black": return .white
    case "화이트", "white": return .black
    case "투명", "clear": return .gray
    case "커스텀", "custom": return .red
    default: return .white  // 기본 배경이 블랙이므로 텍스트는 화이트
    }
  }
  
  // MARK: - Persist
  init() {
    load()
  }

  func load() {
    let d = UserDefaults.standard
    selectedFont = d.string(forKey: "selectedFont") ?? "SF Pro"
    fontSize = CGFloat(d.double(forKey: "fontSize") == 0 ? 24 : d.double(forKey: "fontSize"))
    selectedBackground = d.string(forKey: "selectedBackground") ?? "black"
    isSoundEnabled = d.bool(forKey: "isSoundEnabled")
    isShortcutEnabled = d.bool(forKey: "isShortcutEnabled")
  }

  func save() {
    let d = UserDefaults.standard
    d.set(selectedFont, forKey: "selectedFont")
    d.set(Double(fontSize), forKey: "fontSize")
    d.set(selectedBackground, forKey: "selectedBackground")
    d.set(isSoundEnabled, forKey: "isSoundEnabled")
    d.set(isShortcutEnabled, forKey: "isShortcutEnabled")
  }
}
