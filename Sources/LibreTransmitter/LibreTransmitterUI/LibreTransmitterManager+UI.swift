//
//  LibreTransmitterManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import Combine


public struct LibreTransmitterSetupView: UIViewControllerRepresentable {
    public init(setup: ((LibreTransmitterManager) -> Void)? = nil , completion: (() -> Void)? = nil) {
        self.setup = setup
        self.completion = completion
    }

    public class Coordinator: CompletionDelegate, CGMManagerSetupViewControllerDelegate {
        public func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: CGMManagerUI) {
            setup?(cgmManager as! LibreTransmitterManager)
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
        manager.settingsViewController(for: .milligramsPerDeciliter, glucoseTintColor: .green, guidanceColors: GuidanceColors())
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension LibreTransmitterManager: CGMManagerUI {

    public func settingsViewController(for glucoseUnit: HKUnit, glucoseTintColor: Color, guidanceColors: GuidanceColors) -> (UIViewController & CompletionNotifying) {


        let doneNotifier = GenericObservableObject()
        let wantToTerminateNotifier = GenericObservableObject()


        let settings = SettingsView.asHostedViewController(
            glucoseUnit: glucoseUnit,
            //displayGlucoseUnitObservable: displayGlucoseUnitObservable,
            notifyComplete: doneNotifier, notifyDelete: wantToTerminateNotifier, transmitterInfoObservable: self.transmitterInfoObservable, sensorInfoObervable: self.sensorInfoObservable, glucoseInfoObservable: self.glucoseInfoObservable, alarmStatus: self.alarmStatus)



        let nav = SettingsNavigationViewController(rootViewController: settings)

        doneNotifier.listenOnce { [weak nav] in
            nav?.notifyComplete()

        }

        wantToTerminateNotifier.listenOnce { [weak self] in
            self?.logger.debug("CGM wants to terminate")
            self?.disconnect()
        }

        return nav
    }
}

extension LibreTransmitterManager: DeviceManagerUI {
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier) {
        
    }

    public convenience init?(rawState: RawStateValue) {
        return nil
    }

    public var rawState: RawStateValue {
        [:]
    }

    public var smallImage: UIImage? {
       self.getSmallImage()
    }
}
