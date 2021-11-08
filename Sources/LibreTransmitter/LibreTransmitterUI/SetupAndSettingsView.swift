//
//  File.swift
//  
//
//  Created by Ivan Valkou on 08.11.2021.
//

import UIKit
import SwiftUI

public struct LibreTransmitterSetupView: UIViewControllerRepresentable {
    public init(setup: ((LibreTransmitterManager) -> Void)? = nil , completion: (() -> Void)? = nil) {
        self.setup = setup
        self.completion = completion
    }

    public class Coordinator: CompletionDelegate, CGMManagerSetupViewControllerDelegate {
        public func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: LibreTransmitterManager) {
            setup?(cgmManager)
        }

        public func completionNotifyingDidComplete(_ object: CompletionNotifying) {
            completion?()
        }

        init(completion: (() -> Void)?, setup: ((LibreTransmitterManager) -> Void)?) {
            self.completion = completion
            self.setup = setup
        }

        let completion: (() -> Void)?
        let setup: ((LibreTransmitterManager) -> Void)?
    }

    let setup: ((LibreTransmitterManager) -> Void)?
    let completion: (() -> Void)?


    public func makeUIViewController(context: Context) -> UIViewController {
        let controller = LibreTransmitterSetupViewController()
        controller.completionDelegate = context.coordinator
        controller.setupDelegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion, setup: setup)
    }
}

public struct LibreTransmitterSettingsView: UIViewControllerRepresentable {
    let manager: LibreTransmitterManager
    public init(manager: LibreTransmitterManager) {
        self.manager = manager
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        manager.settingsViewController(for: .millimolesPerLiter)
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
