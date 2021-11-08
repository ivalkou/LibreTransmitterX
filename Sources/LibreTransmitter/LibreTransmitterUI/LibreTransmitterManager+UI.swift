//
//  LibreTransmitterManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import Combine

extension LibreTransmitterManager {
    public func settingsViewController(for glucoseUnit: HKUnit) -> (UIViewController & CompletionNotifying) {

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
