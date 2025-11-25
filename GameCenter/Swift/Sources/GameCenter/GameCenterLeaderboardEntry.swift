//
//  GameCenterLeaderboardEntry.swift
//  GameCenter
//
//  Created by Michael Morris on 11/23/25.
//

import GameKit
import SwiftGodot

@Godot
class GameCenterLeaderboardEntry: Object {
    // MARK: Export
    /// @Export
    /// The player who earned this score
    @Export var player: GameCenterPlayer?
    /// @Export
    /// The score value
    @Export var score: Int = 0
    /// @Export
    /// The player's rank (1 = first place)
    @Export var rank: Int = 0
    /// @Export
    /// Developer-supplied context value
    @Export var context: Int = 0
    
    // NOTE: The date field is commented out because accessing entry.date
    // causes a crash when bridging from Objective-C on some iOS versions.
    // Error: "Date._unconditionallyBridgeFromObjectiveC" in crash logs.
    // Since we don't currently use the date field, it's disabled.
    // To re-enable, uncomment the field and add safe unwrapping in init.
    //
    // /// @Export
    // /// Date the score was earned
    // @Export var date: Double = 0
    
    convenience init(_ entry: GKLeaderboard.Entry) {
        self.init()
        self.player = GameCenterPlayer(entry.player)
        self.score = entry.score
        self.rank = entry.rank
        self.context = entry.context
        // See NOTE above - date access disabled due to crash
        // self.date = entry.date.timeIntervalSince1970
    }
}
