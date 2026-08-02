//
//  main.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import AppKit
import Foundation

let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

#if DEBUG
    let isDebugBuild = true
#else
    let isDebugBuild = false
#endif

#if !DEBUG && !CICADA_DISABLE_SIGNATURE_VALIDATION
    fclose(stdout)
    fclose(stderr)

    Security.removeDebugger()
    guard Security.validateAppSignature() else {
        Security.crashOut()
    }
#endif

#if CICADA_DISABLE_SIGNATURE_VALIDATION
    let allowsLocalUnsignedLaunch = true
#else
    let allowsLocalUnsignedLaunch = false
#endif

let startupLaunchDecision = StartupLaunchPolicy.evaluate(
    isRunningTests: isRunningTests,
    isDebugBuild: isDebugBuild,
    isSandboxEnabled: isRunningTests ? true : SandboxEnvironmentProbe().isSandboxEnabled(),
    allowsLocalUnsignedLaunch: allowsLocalUnsignedLaunch
)

switch startupLaunchDecision {
case .allow:
    break
case let .allowWithDiagnostics(diagnostics):
    PendingStartupDiagnostics.publish(diagnostics)
case let .block(message):
    fatalError(message)
}

let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let videoClipDir = documentDir.appendingPathComponent("VideoClip")

CicadaApp.main()
