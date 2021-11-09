//
//  StateModel.swift
//  LibreTramsmitterExample
//
//  Created by Ivan Valkou on 09.11.2021.
//

import SwiftUI
import LibreTransmitter

final class StateModel: ObservableObject {
    private let delegateQueue = DispatchQueue(label: "StateModel.delegateQueue")

    init () {

    }
}

extension StateModel: LibreTransmitterManagerDelegate {
    var queue: DispatchQueue {
        delegateQueue
    }

    func startDateToFilterNewData(for: LibreTransmitterManager) -> Date? {
        Date().addingTimeInterval(-3600)
    }

    func cgmManager(_: LibreTransmitterManager, hasNew result: Result<[NewGlucoseSample], Error>) {
        switch result {

        case let .success(data):
            print("ASDF data: \(data)")
        case let .failure(error):
            print("ASDF error: \(error.localizedDescription)")
        }
    }

}
