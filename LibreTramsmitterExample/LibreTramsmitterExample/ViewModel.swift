//
//  ViewModel.swift
//  LibreTramsmitterExample
//
//  Created by Ivan Valkou on 29.10.2021.
//

import LibreTransmitter
import Combine
import SwiftUI

final class ViewModel: ObservableObject {

    let searchManager = BluetoothSearchManager()
    var transmitterManager: LibreTransmitterManager?
    var token: AnyCancellable?

    init() {

        searchManager.startTimer()


        token = searchManager.passThroughMetaData
            .sink { [weak self] (p, meta) in
                print("ASDF " + (p.name ?? "unknown"))
                self?.connect(uuid: p.identifier.uuidString)
            }
    }

    func connect(uuid: String) {
        UserDefaults.standard.preSelectedDevice = uuid

        token?.cancel()
        searchManager.stopTimer()

        transmitterManager = LibreTransmitterManager()

    }
}
