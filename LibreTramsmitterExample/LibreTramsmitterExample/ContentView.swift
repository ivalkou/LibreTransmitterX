//
//  ContentView.swift
//  LibreTramsmitterExample
//
//  Created by Ivan Valkou on 29.10.2021.
//

import SwiftUI
import LibreTransmitter

struct ContentView: View {

    @State var manager = LibreTransmitterManager()
    @State var setupPresented = false
    @State var settingsPresented = false

    var body: some View {
        VStack(spacing: 100) {
            Button("Setup") {
                setupPresented = true
            }
            Button("Settings") {
                settingsPresented = true
            }
        }
        .sheet(isPresented: $setupPresented) {

        } content: {
            LibreTransmitterSetupView { manager in
                print("ASDF: manager \(String(describing: manager.metaData))")
            } completion: {
                print("ASDF: done")
            }
        }
        .sheet(isPresented: $settingsPresented) {

        } content: {
            LibreTransmitterSettingsView(manager: manager)
        }
    }
}
