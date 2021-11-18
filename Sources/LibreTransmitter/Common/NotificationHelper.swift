//
//  NotificationHelper.swift
//  MiaomiaoClient
//
//  Created by Bjørn Inge Berg on 30/05/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import AudioToolbox
import Foundation
import HealthKit
import UserNotifications
import os.log
import UIKit
import AudioToolbox

fileprivate var logger = Logger(forType: "NotificationHelper")

public enum NotificationHelper {

    private enum Identifiers: String {
        case glucocoseNotifications = "no.bjorninge.miaomiao.glucose-notification"
        case noSensorDetected = "no.bjorninge.miaomiao.nosensordetected-notification"
        case tryAgainLater = "no.bjorninge.miaomiao.glucoseNotAvailableTryAgainLater-notification"
        case sensorChange = "no.bjorninge.miaomiao.sensorchange-notification"
        case invalidSensor = "no.bjorninge.miaomiao.invalidsensor-notification"
        case lowBattery = "no.bjorninge.miaomiao.lowbattery-notification"
        case sensorExpire = "no.bjorninge.miaomiao.SensorExpire-notification"
        case noBridgeSelected = "no.bjorninge.miaomiao.noBridgeSelected-notification"
        case bluetoothPoweredOff = "no.bjorninge.miaomiao.bluetoothPoweredOff-notification"
        case invalidChecksum = "no.bjorninge.miaomiao.invalidChecksum-notification"
        case calibrationOngoing = "no.bjorninge.miaomiao.calibration-notification"
        case restoredState = "no.bjorninge.miaomiao.state-notification"
    }

    public static func playSoundIfNeeded(count: Int = 3) {
        if UserDefaults.standard.mmGlucoseAlarmsVibrate {
            playSound(times: count)
        }
    }

    private static func playSound(times: Int) {
        guard times > 0 else {
            return
        }

        AudioServicesPlaySystemSoundWithCompletion(SystemSoundID(1336)) {
            playSound(times: times - 1)
        }
    }

    public static func GlucoseUnitIsSupported(unit: HKUnit) -> Bool {
        [HKUnit.milligramsPerDeciliter, HKUnit.millimolesPerLiter].contains(unit)
    }

    public static func sendRestoredStateNotification(msg: String) {
        ensureCanSendNotification {
            logger.debug("dabear:: sending RestoredStateNotification")

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("State was restored", comment: "State was restored")
            content.body = msg

            addRequest(identifier: .restoredState, content: content )
        }
    }

    public static func sendBluetoothPowerOffNotification() {
        ensureCanSendNotification {
            logger.debug("dabear:: sending BluetoothPowerOffNotification")

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Bluetooth Power Off", comment: "Bluetooth Power Off")
            content.body = NSLocalizedString("Please turn on Bluetooth", comment: "Please turn on Bluetooth")

            addRequest(identifier: .bluetoothPoweredOff, content: content)
        }
    }

    public static func sendNoTransmitterSelectedNotification() {
        ensureCanSendNotification {
            logger.debug("dabear:: sending NoTransmitterSelectedNotification")

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("No Libre Transmitter Selected", comment: "No Libre Transmitter Selected")
            content.body = NSLocalizedString("Delete Transmitter and start anew.", comment: "Delete Transmitter and start anew.")

            addRequest(identifier: .noBridgeSelected, content: content)
        }
    }

    private static func ensureCanSendGlucoseNotification(_ completion: @escaping (_ unit: HKUnit) -> Void ) {
        ensureCanSendNotification {
            if let glucoseUnit = UserDefaults.standard.mmGlucoseUnit, GlucoseUnitIsSupported(unit: glucoseUnit) {
                completion(glucoseUnit)
            }
        }
    }

    public static func requestNotificationPermissionsIfNeeded(){
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            logger.debug("settings.authorizationStatus: \(String(describing: settings.authorizationStatus.rawValue))")
            if ![.authorized,.provisional].contains(settings.authorizationStatus) {
                requestNotificationPermissions()
            }

        }

    }

    private static func requestNotificationPermissions() {
        logger.debug("requestNotificationPermissions called")
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
            if granted {
                logger.debug("requestNotificationPermissions was granted")
            } else {
                logger.debug("requestNotificationPermissions failed because of error: \(String(describing: error))")
            }

        }


    }

    private static func ensureCanSendNotification(_ completion: @escaping () -> Void ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.debug("dabear:: ensureCanSendNotification failed, authorization denied")
                return
            }

            logger.debug("dabear:: sending notification was allowed")

            completion()
        }
    }

    public static func sendInvalidChecksumIfDeveloper(_ sensorData: SensorData) {
        if sensorData.hasValidCRCs {
            return
        }

        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Invalid libre checksum", comment: "Invalid libre checksum")
            content.body = NSLocalizedString("Libre sensor was incorrectly read, CRCs were not valid", comment: "Libre sensor was incorrectly read, CRCs were not valid")

            addRequest(identifier: .invalidChecksum, content: content)
        }
    }

    private static var glucoseNotifyCalledCount = 0

    public static func sendGlucoseNotitifcationIfNeeded(glucose: LibreGlucose, oldValue: LibreGlucose?, trend: GlucoseTrend?, battery: String?) {
        glucoseNotifyCalledCount &+= 1

        let shouldSendGlucoseAlternatingTimes = glucoseNotifyCalledCount != 0 && UserDefaults.standard.mmNotifyEveryXTimes != 0

        let shouldSend = UserDefaults.standard.mmAlwaysDisplayGlucose || glucoseNotifyCalledCount == 1 || (shouldSendGlucoseAlternatingTimes && glucoseNotifyCalledCount % UserDefaults.standard.mmNotifyEveryXTimes == 0)

        let schedules = UserDefaults.standard.glucoseSchedules

        let alarm = schedules?.getActiveAlarms(glucose.glucoseDouble) ?? .none
        let isSnoozed = GlucoseScheduleList.isSnoozed()

        let shouldShowPhoneBattery = UserDefaults.standard.mmShowPhoneBattery
        let transmitterBattery = UserDefaults.standard.mmShowTransmitterBattery && battery != nil ? battery : nil

        logger.debug("dabear:: glucose alarmtype is \(String(describing:alarm))")
        // We always send glucose notifications when alarm is active,
        // even if glucose notifications are disabled in the UI

        if shouldSend || alarm.isAlarming() {
            sendGlucoseNotitifcation(glucose: glucose, oldValue: oldValue, alarm: alarm, isSnoozed: isSnoozed, trend: trend, showPhoneBattery: shouldShowPhoneBattery, transmitterBattery: transmitterBattery)
        } else {
            logger.debug("dabear:: not sending glucose, shouldSend and alarmIsActive was false")
            return
        }
    }

    private static func addRequest(identifier: Identifiers, content: UNMutableNotificationContent, deleteOld: Bool = false) {
        let center = UNUserNotificationCenter.current()
        //content.sound = UNNotificationSound.
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: nil)

        if deleteOld {
            // Required since ios12+ have started to cache/group notifications
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        center.add(request) { error in
            if let error = error {
                logger.debug("dabear:: unable to addNotificationRequest: \(error.localizedDescription)")
                return
            }

            logger.debug("dabear:: sending \(identifier.rawValue) notification")
        }
    }
    private static func sendGlucoseNotitifcation(glucose: LibreGlucose, oldValue: LibreGlucose?, alarm: GlucoseScheduleAlarmResult = .none, isSnoozed: Bool = false, trend: GlucoseTrend?, showPhoneBattery: Bool = false, transmitterBattery: String?) {
        ensureCanSendGlucoseNotification { _ in
            let content = UNMutableNotificationContent()
            let glucoseDesc = glucose.description
            var titles = [String]()
            var body = [String]()
            var body2 = [String]()
            switch alarm {
            case .none:
                titles.append(LocalizedString("Glucose", comment: "Glucose"))
            case .low:
                titles.append(LocalizedString("LOWALERT!", comment: "LOWALERT!"))
            case .high:
                titles.append(LocalizedString("HIGHALERT!", comment: "HIGHALERT!"))
            }

            if isSnoozed {
                titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
            } else if alarm.isAlarming() {
                content.sound = .default
                playSoundIfNeeded()
            }
            titles.append(glucoseDesc)

            body.append(String(format: NSLocalizedString("Glucose: %@", comment: "Glucose: %@"), glucoseDesc))

            if let oldValue = oldValue {
                body.append( LibreGlucose.glucoseDiffDesc(oldValue: oldValue, newValue: glucose))
            }

            if let trendSymbol = trend?.symbol {
                body.append("\(trendSymbol)")
            }

            if showPhoneBattery {
                if !UIDevice.current.isBatteryMonitoringEnabled {
                    UIDevice.current.isBatteryMonitoringEnabled = true
                }

                let battery = Double(UIDevice.current.batteryLevel * 100 ).roundTo(places: 1)
                body2.append(String(format: NSLocalizedString("Phone: %@%%", comment: "Phone: %@%%"), battery))
            }

            if let transmitterBattery = transmitterBattery {
                body2.append(String(format: NSLocalizedString("Transmitter: %@", comment: "Transmitter: %@"), transmitterBattery))
            }

            //these are texts that naturally fit on their own line in the body
            var body2s = ""
            if !body2.isEmpty {
                body2s = "\n" + body2.joined(separator: "\n")
            }

            content.title = titles.joined(separator: " ")
            content.body = body.joined(separator: ", ") + body2s
            addRequest(identifier: .glucocoseNotifications,
                       content: content,
                       deleteOld: true)
        }
    }

    public enum CalibrationMessage: String {
        case starting = "Calibrating sensor, please stand by!"
        case noCalibration = "Could not calibrate sensor, check libreoopweb permissions and internet connection"
        case invalidCalibrationData = "Could not calibrate sensor, invalid calibrationdata"
        case success = "Success!"
    }

    public static func sendCalibrationNotification(_ calibrationMessage: CalibrationMessage) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = NSLocalizedString("Extracting calibrationdata from sensor", comment: "Extracting calibrationdata from sensor")
            content.body = NSLocalizedString(calibrationMessage.rawValue, comment: "calibrationMessage")

            addRequest(identifier: .calibrationOngoing,
                       content: content,
                       deleteOld: true)
        }
    }

    public static func sendSensorNotDetectedNotificationIfNeeded(noSensor: Bool) {
        guard UserDefaults.standard.mmAlertNoSensorDetected && noSensor else {
            logger.debug("Not sending noSensorDetected notification")
            return
        }

        sendSensorNotDetectedNotification()
    }

    private static func sendSensorNotDetectedNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("No Sensor Detected", comment: "No Sensor Detected")
            content.body = NSLocalizedString("This might be an intermittent problem, but please check that your transmitter is tightly secured over your sensor", comment: "This might be an intermittent problem, but please check that your transmitter is tightly secured over your sensor")

            addRequest(identifier: .noSensorDetected, content: content)
        }
    }

    public static func sendSensorChangeNotificationIfNeeded() {
        guard UserDefaults.standard.mmAlertNewSensorDetected else {
            logger.debug("not sending sendSensorChange notification ")
            return
        }
        sendSensorChangeNotification()
    }

    private static func sendSensorChangeNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("New Sensor Detected", comment: "New Sensor Detected")
            content.body = NSLocalizedString("Please wait up to 30 minutes before glucose readings are available!", comment: "Please wait up to 30 minutes before glucose readings are available!")

            addRequest(identifier: .sensorChange, content: content)
            //content.sound = UNNotificationSound.

        }
    }

    public static func sendSensorTryAgainLaterNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Invalid Glucose sample detected, try again later", comment: "Invalid Glucose sample detected, try again later")
            content.body = NSLocalizedString("Sensor might have temporarily stopped, fallen off or is too cold or too warm", comment: "Sensor might have temporarily stopped, fallen off or is too cold or too warm")

            addRequest(identifier: .tryAgainLater, content: content)
            //content.sound = UNNotificationSound.

        }
    }



    public static func sendInvalidSensorNotificationIfNeeded(sensorData: SensorData) {
        let isValid = sensorData.isLikelyLibre1FRAM && (sensorData.state == .starting || sensorData.state == .ready)

        guard UserDefaults.standard.mmAlertInvalidSensorDetected && !isValid else {
            logger.debug("not sending invalidSensorDetected notification")
            return
        }

        sendInvalidSensorNotification(sensorData: sensorData)
    }

    private static func sendInvalidSensorNotification(sensorData: SensorData) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Invalid Sensor Detected", comment: "Invalid Sensor Detected")

            if !sensorData.isLikelyLibre1FRAM {
                content.body = NSLocalizedString("Detected sensor seems not to be a libre 1 sensor!", comment: "Detected sensor seems not to be a libre 1 sensor!")
            } else if !(sensorData.state == .starting || sensorData.state == .ready) {
                content.body = String(format: NSLocalizedString("Detected sensor is invalid: %@", comment: "Detected sensor is invalid: %@"), sensorData.state.description)
            }

            content.sound = .default

            addRequest(identifier: .invalidSensor, content: content)
        }
    }

    private static var lastBatteryWarning: Date?

    public static func sendLowBatteryNotificationIfNeeded(device: LibreTransmitterMetadata) {
        guard UserDefaults.standard.mmAlertLowBatteryWarning else {
            logger.debug("mmAlertLowBatteryWarning toggle was not enabled, not sending low notification")
            return
        }

        if let battery = device.battery, battery > 20 {
            logger.debug("device battery is \(battery), not sending low notification")
            return

        }

        let now = Date()
        //only once per mins minute
        let mins = 60.0 * 120
        if let earlierplus = lastBatteryWarning?.addingTimeInterval(mins) {
            if earlierplus < now {
                sendLowBatteryNotification(batteryPercentage: device.batteryString,
                                           deviceName: device.name)
                lastBatteryWarning = now
            } else {
                logger.debug("Device battery is running low, but lastBatteryWarning Notification was sent less than 45 minutes ago, aborting. earlierplus: \(earlierplus), now: \(now)")
            }
        } else {
            sendLowBatteryNotification(batteryPercentage: device.batteryString,
                                       deviceName: device.name)
            lastBatteryWarning = now
        }
    }

    private static func sendLowBatteryNotification(batteryPercentage: String, deviceName: String) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Low Battery", comment: "Low Battery")
            content.body = String(format: NSLocalizedString("Battery is running low %@, consider charging your %@ device as soon as possible", comment: ""), batteryPercentage, deviceName)


            content.sound = .default

            addRequest(identifier: .lowBattery, content: content)
        }
    }

    private static var lastSensorExpireAlert: Date?

    public static func sendSensorExpireAlertIfNeeded(minutesLeft: Double) {
        guard UserDefaults.standard.mmAlertWillSoonExpire else {
            logger.debug("mmAlertWillSoonExpire toggle was not enabled, not sending expiresoon alarm")
            return
        }

        guard TimeInterval(minutes: minutesLeft) < TimeInterval(hours: 24) else {
            logger.debug("Sensor time left was more than 24 hours, not sending notification: \(minutesLeft.twoDecimals) minutes")
            return
        }

        let now = Date()
        //only once per 6 hours
        let min45 = 60.0 * 60 * 6

        if let earlier = lastSensorExpireAlert {
            if earlier.addingTimeInterval(min45) < now {
                sendSensorExpireAlert(minutesLeft: minutesLeft)
                lastSensorExpireAlert = now
            } else {
                logger.debug("Sensor is soon expiring, but lastSensorExpireAlert was sent less than 6 hours ago, so aborting")
            }
        } else {
            sendSensorExpireAlert(minutesLeft: minutesLeft)
            lastSensorExpireAlert = now
        }
    }

    public static func sendSensorExpireAlertIfNeeded(sensorData: SensorData) {
        sendSensorExpireAlertIfNeeded(minutesLeft: Double(sensorData.minutesLeft))
    }

    private static func sendSensorExpireAlert(minutesLeft: Double) {
        ensureCanSendNotification {

            let hours = minutesLeft == 0 ? 0 : round(minutesLeft/60)

            let dynamicText =  hours <= 1 ?  "minutes: \(minutesLeft.twoDecimals)" : "hours: \(hours.twoDecimals)"

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Sensor Ending Soon", comment: "Sensor Ending Soon")
            content.body = String(format: NSLocalizedString("Current Sensor is Ending soon! Sensor Life left in %@", comment: ""), dynamicText)

            addRequest(identifier: .sensorExpire, content: content, deleteOld: true)
        }
    }
}
