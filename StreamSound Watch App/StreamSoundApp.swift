//
//  StreamSoundApp.swift
//  StreamSound Watch App
//
//  Created by Pixie on 17/09/2025.
//

import SwiftUI
import SwiftData

@main
struct StreamSound_Watch_AppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([YouTubeAudio.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            NavigationStack { MainListView() }
        }
        .modelContainer(sharedModelContainer)
    }
}
