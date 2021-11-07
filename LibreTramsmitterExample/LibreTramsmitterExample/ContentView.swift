//
//  ContentView.swift
//  LibreTramsmitterExample
//
//  Created by Ivan Valkou on 29.10.2021.
//

import SwiftUI
import LibreTransmitter

struct ContentView: View {
    @StateObject var viewModel = ViewModel()

    @State var manager = LibreTransmitterManager()

    var body: some View {
//        LibreTransmitterSetupView { manager in
//            print("ASDF: manager \(manager.metaData)")
//        } completion: {
//            print("ASDF: done")
//        }

        LibreTransmitterSettingsView(manager: manager)
    }
}
