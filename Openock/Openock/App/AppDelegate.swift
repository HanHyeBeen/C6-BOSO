//
//  AppDelegate.swift
//  Openock
//
//  Created by JiJooMaeng on 10/26/25.
//


import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var windowDidBecomeKey: Bool = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    
    NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
      self?.windowDidBecomeKey = true
    }
  }
}
