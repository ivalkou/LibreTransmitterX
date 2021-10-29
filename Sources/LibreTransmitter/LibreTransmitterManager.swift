//
//  LibreTransmitterManager.swift
//  Created by Bjørn Inge Berg on 25/02/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation
import UIKit
import UserNotifications
import Combine

import CoreBluetooth
import HealthKit
import os.log

public final class LibreTransmitterManager: LibreTransmitterDelegate {
    public typealias GlucoseArrayWithPrediction = (glucose:[LibreGlucose], prediction:[LibreGlucose])
    public lazy var logger = Logger(forType: Self.self)

    public var hasValidSensorSession: Bool {
        lastConnected != nil 
    }

    public var glucoseDisplay: GlucoseDisplayable?

    public func libreManagerDidRestoreState(found peripherals: [CBPeripheral], connected to: CBPeripheral?) {
        let devicename = to?.name  ?? "no device"
        let id = to?.identifier.uuidString ?? "null"
        let msg = "Bluetooth State restored (Loop restarted?). Found \(peripherals.count) peripherals, and connected to \(devicename) with identifier \(id)"
        print(msg)
    }

    public var batteryLevel: Double? {
        let batt = self.proxy?.metadata?.battery
        logger.debug("dabear:: LibreTransmitterManager was asked to return battery: \(batt.debugDescription)")
        //convert from 8% -> 0.8
        if let battery = proxy?.metadata?.battery {
            return Double(battery) / 100
        }

        return nil
    }

    public var managedDataInterval: TimeInterval?

    private func getPersistedSensorDataForDebug() -> String {
        guard let data = UserDefaults.standard.queuedSensorData else {
            return "nil"
        }

        let c = self.calibrationData?.description ?? "no calibrationdata"
        return data.array.map {
            "SensorData(uuid: \"0123\".data(using: .ascii)!, bytes: \($0.bytes))!"
        }
        .joined(separator: ",\n")
        + ",\n Calibrationdata: \(c)"
    }

    public var debugDescription: String {

        return [
            "## LibreTransmitterManager",
            "Testdata: foo",
            "lastConnected: \(String(describing: lastConnected))",
            "Connection state: \(connectionState)",
            "Sensor state: \(sensorStateDescription)",
            "transmitterbattery: \(batteryString)",
            "SensorData: \(getPersistedSensorDataForDebug())",
            "Metainfo::\n\(AppMetaData.allProperties)",
            ""
        ].joined(separator: "\n")
    }

    public private(set) var lastConnected: Date?

    public private(set) var alarmStatus = AlarmStatus()


    public private(set) var latestPrediction: LibreGlucose?
    public private(set) var latestBackfill: LibreGlucose? {
        willSet(newValue) {
            guard let newValue = newValue else {
                return
            }

            var trend: GlucoseTrend?
            let oldValue = latestBackfill

            defer {
                logger.debug("dabear:: sending glucose notification")

                //once we have a new glucose value, we can update the isalarming property
                if let activeAlarms = UserDefaults.standard.glucoseSchedules?.getActiveAlarms(newValue.glucoseDouble) {
                    DispatchQueue.main.async {
                        self.alarmStatus.isAlarming = ([.high,.low].contains(activeAlarms))
                        self.alarmStatus.glucoseScheduleAlarmResult = activeAlarms
                    }
                } else {
                    DispatchQueue.main.async {
                    self.alarmStatus.isAlarming = false
                    self.alarmStatus.glucoseScheduleAlarmResult = .none
                    }
                }


            }

//            logger.debug("dabear:: latestBackfill set, newvalue is \(newValue.description)")

            if let oldValue = oldValue {
                // the idea here is to use the diff between the old and the new glucose to calculate slope and direction, rather than using trend from the glucose value.
                // this is because the old and new glucose values represent earlier readouts, while the trend buffer contains somewhat more jumpy (noisy) values.
                let timediff = LibreGlucose.timeDifference(oldGlucose: oldValue, newGlucose: newValue)
                logger.debug("dabear:: timediff is \(timediff)")
                let oldIsRecentEnough = timediff <= TimeInterval.minutes(15)

                trend = oldIsRecentEnough ? newValue.GetGlucoseTrend(last: oldValue) : nil

                var batteries : [(name: String, percentage: Int)]?
                if let metaData = metaData, let battery = battery {
                    batteries = [(name: metaData.name, percentage: battery)]
                }

                self.glucoseDisplay = ConcreteGlucoseDisplayable(isStateValid: newValue.isStateValid, trendType: trend, isLocal: true, batteries: batteries)
            } else {
                //could consider setting this to ConcreteSensorDisplayable with trendtype GlucoseTrend.flat, but that would be kinda lying
                self.glucoseDisplay = nil
            }
        }

    }

    static public var managerIdentifier : String {
        Self.className
    }

    static public let localizedTitle = LocalizedString("Libre Bluetooth", comment: "Title for the CGMManager option")


    public init() {
        lastConnected = nil
        //let isui = (self is CGMManagerUI)
        //self.miaomiaoService = MiaomiaoService(keychainManager: keychain)

        logger.debug("dabear: LibreTransmitterManager will be created now")
        //proxy = MiaoMiaoBluetoothManager()
        proxy?.delegate = self
    }

    public func disconnect() {
        logger.debug("dabear:: LibreTransmitterManager disconnect called")

        proxy?.disconnectManually()
        proxy?.delegate = nil
    }

    deinit {
        logger.debug("dabear:: LibreTransmitterManager deinit called")
        //cleanup any references to events to this class
        disconnect()
    }

    //lazy because we don't want to scan immediately
    private lazy var proxy: LibreTransmitterProxyManager? = LibreTransmitterProxyManager()

    /*
     These properties are mostly useful for swiftui
     */
    public var transmitterInfoObservable = TransmitterInfo()
    public var sensorInfoObservable = SensorInfo()
    public var glucoseInfoObservable = GlucoseInfo()

    var longDateFormatter : DateFormatter = ({
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .long
        df.doesRelativeDateFormatting = true
        return df
    })()

    var dateFormatter : DateFormatter = ({
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .full
        df.locale = Locale.current
        return df
    })()


    //when was the libre2 direct ble update last received?
    var lastDirectUpdate : Date? = nil

    private var countTimesWithoutData: Int = 0


}


// MARK: - Convenience functions
extension LibreTransmitterManager {

    public var calibrationData: SensorData.CalibrationInfo? {
        KeychainManagerWrapper.standard.getLibreNativeCalibrationData()
    }
}


// MARK: - Direct bluetooth updates
extension LibreTransmitterManager {

    public func libreSensorDidUpdate(with bleData: Libre2.LibreBLEResponse, and Device: LibreTransmitterMetadata) {
        self.logger.debug("dabear:: got sensordata: \(String(describing: bleData))")
        let typeDesc = Device.sensorType().debugDescription

        let now = Date()
        //only once per mins minute
        let mins =  4.5
        if let earlierplus = lastDirectUpdate?.addingTimeInterval(mins * 60), earlierplus >= now  {
            logger.debug("last ble update was less than \(mins) minutes ago, aborting loop update")
            return
        }

        logger.debug("Directly connected to libresensor of type \(typeDesc). Details:  \(Device.description)")

        guard let mapping = UserDefaults.standard.calibrationMapping,
              let calibrationData = calibrationData,
              let sensor = UserDefaults.standard.preSelectedSensor else {
            logger.error("calibrationdata, sensor uid or mapping missing, could not continue")
//            self.delegateQueue.async {
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.noCalibrationData))
//            }
            return
        }

        guard mapping.reverseFooterCRC == calibrationData.isValidForFooterWithReverseCRCs &&
                mapping.uuid == sensor.uuid else {
            logger.error("Calibrationdata was not correct for these bluetooth packets. This is a fatal error, we cannot calibrate without re-pairing")
//            self.delegateQueue.async {
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.noCalibrationData))
//            }
            return
        }

        guard bleData.crcVerified else {
//            self.delegateQueue.async {
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.checksumValidationError))
//            }

            logger.debug("did not get bledata with valid crcs")
            return
        }

        if sensor.maxAge > 0 {
            let minutesLeft = Double(sensor.maxAge - bleData.age)
//            NotificationHelper.sendSensorExpireAlertIfNeeded(minutesLeft: minutesLeft)

        }


        let device = self.proxy?.device



        let sortedTrends = bleData.trend.sorted{ $0.date > $1.date}

        var glucose = LibreGlucose.fromTrendMeasurements(sortedTrends, nativeCalibrationData: calibrationData, returnAll: UserDefaults.standard.mmBackfillFromTrend)
        //glucose += LibreGlucose.fromHistoryMeasurements(bleData.history, nativeCalibrationData: calibrationData)

        // while libre2 fram scans contains historymeasurements for the last 8 hours,
        // history from bledata contains just a couple of data points, so we don't bother
        /*if UserDefaults.standard.mmBackfillFromHistory {
            let sortedHistory = bleData.history.sorted{ $0.date > $1.date}
            glucose += LibreGlucose.fromHistoryMeasurements(sortedHistory, nativeCalibrationData: calibrationData)
        }*/

//        let newGlucose = glucosesToSamplesFilter(glucose, startDate: getStartDateForFilter())
        /*glucose
            .filter { $0.isStateValid }
            .compactMap {
                return NewGlucoseSample(date: $0.startDate,
                             quantity: $0.quantity,
                             isDisplayOnly: false,
                             wasUserEntered: false,
                             syncIdentifier: $0.syncId,
                             device: device)
            }*/


        if glucose.isEmpty {
            self.countTimesWithoutData &+= 1
        } else {
            self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
            self.logger.debug("dabear:: latestbackfill set to \(self.latestBackfill.debugDescription)")
            self.countTimesWithoutData = 0
        }

        //todo: predictions also for libre2 bluetooth data
        //self.latestPrediction = prediction?.first

//        self.setObservables(sensorData: nil, bleData: bleData, metaData: Device)

//        self.logger.debug("dabear:: handleGoodReading returned with \(newGlucose.count) entries")
//        self.delegateQueue.async {
//            var result: CGMReadingResult
//            // If several readings from a valid and running sensor come out empty,
//            // we have (with a large degree of confidence) a sensor that has been
//            // ripped off the body
//            if self.countTimesWithoutData > 1 {
//                result = .error(LibreError.noValidSensorData)
//            } else {
//                result = newGlucose.isEmpty ? .noData : .newData(newGlucose)
//            }
//            self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
//        }

        lastDirectUpdate = Date()


    }
}

// MARK: - Bluetooth transmitter data
extension LibreTransmitterManager {

    public func noLibreTransmitterSelected() {
//        NotificationHelper.sendNoTransmitterSelectedNotification()
    }

    public func libreTransmitterDidUpdate(with sensorData: SensorData, and Device: LibreTransmitterMetadata) {

        self.logger.debug("dabear:: got sensordata: \(String(describing: sensorData)), bytescount: \( sensorData.bytes.count), bytes: \(sensorData.bytes)")
        var sensorData = sensorData

//        self.setObservables(sensorData: nil, bleData: nil, metaData: Device)

         if !sensorData.isLikelyLibre1FRAM {
            if let patchInfo = Device.patchInfo, let sensorType = SensorType(patchInfo: patchInfo) {
                let needsDecryption = [SensorType.libre2, .libreUS14day].contains(sensorType)
                if needsDecryption, let uid = Device.uid {
                    sensorData.decrypt(patchInfo: patchInfo, uid: uid)
                }
            } else {
                logger.debug("Sensor type was incorrect, and no decryption of sensor was possible")
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.encryptedSensor))
                return
            }
        }

        let typeDesc = Device.sensorType().debugDescription

        logger.debug("Transmitter connected to libresensor of type \(typeDesc). Details:  \(Device.description)")

        tryPersistSensorData(with: sensorData)

        guard sensorData.hasValidCRCs else {
//            self.delegateQueue.async {
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.checksumValidationError))
//            }

            logger.debug("did not get sensordata with valid crcs")
            return
        }

        guard sensorData.state == .ready || sensorData.state == .starting else {
            logger.debug("dabear:: got sensordata with valid crcs, but sensor is either expired or failed")
//            self.delegateQueue.async {
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.expiredSensor))
//            }
            return
        }

        logger.debug("dabear:: got sensordata with valid crcs, sensor was ready")
        //self.lastValidSensorData = sensorData



        self.handleGoodReading(data: sensorData) { [weak self] error, glucoseArrayWithPrediction in
            guard let self = self else {
                print("dabear:: handleGoodReading could not lock on self, aborting")
                return
            }
            if let error = error {
                self.logger.error("dabear:: handleGoodReading returned with error: \(error.errorDescription)")
//                self.delegateQueue.async {
//                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(error))
//                }
                return
            }


            guard let glucose = glucoseArrayWithPrediction?.glucose else {
                self.logger.debug("dabear:: handleGoodReading returned with no data")
//                self.delegateQueue.async {
//                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .noData)
//                }
                return
            }

            let prediction = glucoseArrayWithPrediction?.prediction



            let device = self.proxy?.device
//            let newGlucose = self.glucosesToSamplesFilter(glucose, startDate: self.getStartDateForFilter())



            if glucose.isEmpty {
                self.countTimesWithoutData &+= 1
            } else {
                self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
                self.logger.debug("dabear:: latestbackfill set to \(self.latestBackfill.debugDescription)")
                self.countTimesWithoutData = 0
            }

            self.latestPrediction = prediction?.first

            //must be inside this handler as setobservables "depend" on latestbackfill
//            self.setObservables(sensorData: sensorData, bleData: nil, metaData: nil)

//            self.logger.debug("dabear:: handleGoodReading returned with \(newGlucose.count) entries")
//            self.delegateQueue.async {
//                var result: CGMReadingResult
//                // If several readings from a valid and running sensor come out empty,
//                // we have (with a large degree of confidence) a sensor that has been
//                // ripped off the body
//                if self.countTimesWithoutData > 1 {
//                    result = .error(LibreError.noValidSensorData)
//                } else {
//                    result = newGlucose.isEmpty ? .noData : .newData(newGlucose)
//                }
//                self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
//            }
        }

    }
    private func readingToGlucose(_ data: SensorData, calibration: SensorData.CalibrationInfo) -> GlucoseArrayWithPrediction {

        var entries: [LibreGlucose] = []
        var prediction: [LibreGlucose] = []

        let predictGlucose = true

        // Increase to up to 15 to move closer to real blood sugar
        // The cost is slightly more noise on consecutive readings
        let glucosePredictionMinutes : Double = 10

        if predictGlucose {
            // We cheat here by forcing the loop to think that the predicted glucose value is the current blood sugar value.
            logger.debug("Predicting glucose value")
            if let predicted = data.predictBloodSugar(glucosePredictionMinutes){
                let currentBg = predicted.roundedGlucoseValueFromRaw2(calibrationInfo: calibration)
                let bgDate = predicted.date.addingTimeInterval(60 * -glucosePredictionMinutes)

                prediction.append(LibreGlucose(unsmoothedGlucose: currentBg, glucoseDouble: currentBg, timestamp: bgDate))
                logger.debug("Predicted glucose (not used) was: \(currentBg)")
            } else {
                logger.debug("Tried to predict glucose value but failed!")
            }

        }

        let trends = data.trendMeasurements()
        let firstTrend = trends.first?.roundedGlucoseValueFromRaw2(calibrationInfo: calibration)
        logger.debug("first trend was: \(String(describing: firstTrend))")
        entries = LibreGlucose.fromTrendMeasurements(trends, nativeCalibrationData: calibration, returnAll: UserDefaults.standard.mmBackfillFromTrend)

        if UserDefaults.standard.mmBackfillFromHistory {
            let history = data.historyMeasurements()
            entries += LibreGlucose.fromHistoryMeasurements(history, nativeCalibrationData: calibration)
        }



        return (glucose: entries, prediction: prediction)
    }

    public func handleGoodReading(data: SensorData?, _ callback: @escaping (LibreError?, GlucoseArrayWithPrediction?) -> Void) {
        //only care about the once per minute readings here, historical data will not be considered

        guard let data = data else {
            callback(.noSensorData, nil)
            return
        }


        if let calibrationdata = calibrationData {
            logger.debug("dabear:: calibrationdata loaded")

            if calibrationdata.isValidForFooterWithReverseCRCs == data.footerCrc.byteSwapped {
                logger.debug("dabear:: calibrationdata correct for this sensor, returning last values")

                callback(nil, readingToGlucose(data, calibration: calibrationdata))
                return
            } else {
                logger.debug("dabear:: calibrationdata incorrect for this sensor, calibrationdata.isValidForFooterWithReverseCRCs: \(calibrationdata.isValidForFooterWithReverseCRCs),  data.footerCrc.byteSwapped: \(data.footerCrc.byteSwapped)")
            }
        } else {
            logger.debug("dabear:: calibrationdata was nil")
        }

        calibrateSensor(sensordata: data) { [weak self] calibrationparams  in
            do {
                try KeychainManagerWrapper.standard.setLibreNativeCalibrationData(calibrationparams)
            } catch {
                callback(.invalidCalibrationData, nil)
                return
            }
            //here we assume success, data is not changed,
            //and we trust that the remote endpoint returns correct data for the sensor

            callback(nil, self?.readingToGlucose(data, calibration: calibrationparams))
        }
    }

    //will be called on utility queue
    public func libreTransmitterStateChanged(_ state: BluetoothmanagerState) {
        DispatchQueue.main.async {
            self.transmitterInfoObservable.connectionState = self.proxy?.connectionStateString ?? "n/a"
            self.transmitterInfoObservable.transmitterType = self.proxy?.shortTransmitterName ?? "Unknown"
        }
        switch state {
        case .Connected:
            lastConnected = Date()
        case .powerOff:
            break
        default:
            break
        }
        return
    }

    //will be called on utility queue
    public func libreTransmitterReceivedMessage(_ messageIdentifier: UInt16, txFlags: UInt8, payloadData: Data) {
        guard let packet = MiaoMiaoResponseState(rawValue: txFlags) else {
            // Incomplete package?
            // this would only happen if delegate is called manually with an unknown txFlags value
            // this was the case for readouts that were not yet complete
            // but that was commented out in MiaoMiaoManager.swift, see comment there:
            // "dabear-edit: don't notify on incomplete readouts"
            logger.debug("dabear:: incomplete package or unknown response state")
            return
        }

        switch packet {
        case .newSensor:
            logger.debug("dabear:: new libresensor detected")
        case .noSensor:
            logger.debug("dabear:: no libresensor detected")
        case .frequencyChangedResponse:
            logger.debug("dabear:: transmitter readout interval has changed!")

        default:
            //we don't care about the rest!
            break
        }

        return
    }

    func tryPersistSensorData(with sensorData: SensorData) {
        guard UserDefaults.standard.shouldPersistSensorData else {
            return
        }

        //yeah, we really really need to persist any changes right away
        var data = UserDefaults.standard.queuedSensorData ?? LimitedQueue<SensorData>()
        data.enqueue(sensorData)
        UserDefaults.standard.queuedSensorData = data
    }
}

// MARK: - conventience properties to access the enclosed proxy's properties

extension LibreTransmitterManager {
    public var device: HKDevice? {
         //proxy?.OnQueue_device
        proxy?.device
    }

    static var className: String {
        String(describing: Self.self)
    }
    //cannot be called from managerQueue
    public var identifier: String {
        //proxy?.OnQueue_identifer?.uuidString ?? "n/a"
        proxy?.identifier?.uuidString ?? "n/a"
    }

    public var metaData: LibreTransmitterMetadata? {
        //proxy?.OnQueue_metadata
         proxy?.metadata
    }

    //cannot be called from managerQueue
    public var connectionState: String {
        //proxy?.connectionStateString ?? "n/a"
        proxy?.connectionStateString ?? "n/a"
    }
    //cannot be called from managerQueue
    public var sensorSerialNumber: String {
        //proxy?.OnQueue_sensorData?.serialNumber ?? "n/a"
        proxy?.sensorData?.serialNumber ?? "n/a"
    }

    //cannot be called from managerQueue
    public var sensorAge: String {
        //proxy?.OnQueue_sensorData?.humanReadableSensorAge ?? "n/a"
        proxy?.sensorData?.humanReadableSensorAge ?? "n/a"
    }

    public var sensorEndTime : String {
        if let endtime = proxy?.sensorData?.sensorEndTime  {
            let mydf = DateFormatter()
            mydf.dateStyle = .long
            mydf.timeStyle = .full
            mydf.locale = Locale.current
            return mydf.string(from: endtime)
        }
        return "Unknown or Ended"
    }

    public var sensorTimeLeft: String {
        //proxy?.OnQueue_sensorData?.humanReadableSensorAge ?? "n/a"
        proxy?.sensorData?.humanReadableTimeLeft ?? "n/a"
    }

    //cannot be called from managerQueue
    public var sensorFooterChecksums: String {
        //(proxy?.OnQueue_sensorData?.footerCrc.byteSwapped).map(String.init)
        (proxy?.sensorData?.footerCrc.byteSwapped).map(String.init)

            ?? "n/a"
    }



    //cannot be called from managerQueue
    public var sensorStateDescription: String {
        //proxy?.OnQueue_sensorData?.state.description ?? "n/a"
        proxy?.sensorData?.state.description ?? "n/a"
    }
    //cannot be called from managerQueue
    public var firmwareVersion: String {
        proxy?.metadata?.firmware ?? "n/a"
    }

    //cannot be called from managerQueue
    public var hardwareVersion: String {
        proxy?.metadata?.hardware ?? "n/a"
    }

    //cannot be called from managerQueue
    public var batteryString: String {
        proxy?.metadata?.batteryString ?? "n/a"
    }

    public var battery: Int? {
        proxy?.metadata?.battery
    }

    public func getDeviceType() -> String {
        proxy?.shortTransmitterName ?? "Unknown"
    }
    public func getSmallImage() -> UIImage? {
        proxy?.activePluginType?.smallImage ?? UIImage(named: "libresensor", in: Bundle.current, compatibleWith: nil)
    }
}


