//
//  GameCenter+Leaderboards.swift
//  GameCenter
//
//  Created by ZT Pawer on 12/28/24.
//

import GameKit
import SwiftGodot

extension GameCenter {

    func submitScoreInternal(
        _ score: Int, context: Int, player: GKPlayer,
        leaderboardIDs: [String]
    ) {
        guard GKLocalPlayer.local.isAuthenticated == true else {
            self.leaderboardScoreFail.emit(
                GameCenterError.notAuthenticated.rawValue,
                "Player is not authenticated",
                leaderboardIDs.joined(separator: ","))
            return
        }
        
        GKLeaderboard.submitScore(
            score, context: context, player: player,
            leaderboardIDs: leaderboardIDs,
            completionHandler: { error in
                guard error == nil else {
                    self.leaderboardScoreFail.emit(
                        (error! as NSError).code,
                        "Error while submitting score",
                        leaderboardIDs.joined(separator: ","))
                    return
                }
                self.leaderboardScoreSuccess.emit(leaderboardIDs.joined(separator: ","))
            })
    }

    func showLeaderboardsInternal() {
        #if canImport(UIKit)
            viewController.showUIController(
                GKGameCenterViewController(state: .leaderboards),
                completitionHandler: { status in
                    switch status {
                    case GameCenterUIState.success.rawValue:
                        self.leaderboardSuccess.emit()
                    case GameCenterUIState.dismissed.rawValue:
                        self.leaderboardDismissed.emit()
                    default:
                        self.leaderboardFail.emit(GameCenterError.unknownError.rawValue, "Unknown error")
                    }
                })
        #endif
    }

    func showLeaderboardInternal(leaderboardID: String) {
        #if canImport(UIKit)
            viewController.showUIController(
                GKGameCenterViewController(
                    leaderboardID: leaderboardID,
                    playerScope: .global,
                    timeScope: .allTime
                ),
                completitionHandler: { status in
                    switch status {
                    case GameCenterUIState.success.rawValue:
                        self.leaderboardSuccess.emit()
                    case GameCenterUIState.dismissed.rawValue:
                        self.leaderboardDismissed.emit()
                    default:
                        self.leaderboardFail.emit(GameCenterError.unknownError.rawValue, "Unknown error")
                    }
                })
        #else
            leaderboardFail.emit(
                GameCenterError.notAvailable.rawValue,
                "Leaderboard not available")
        #endif
    }

    func loadLeaderboardEntriesInternal(
        leaderboardID: String,
        playerScope: String,
        timeScope: String,
        rankMin: Int,
        rankMax: Int
    ) {
        guard GKLocalPlayer.local.isAuthenticated == true else {
            self.leaderboardEntriesLoadFail.emit(
                GameCenterError.notAuthenticated.rawValue,
                "Player is not authenticated",
                leaderboardID)
            return
        }
        
        // Convert string parameters to enums
        let gkPlayerScope: GKLeaderboard.PlayerScope = (playerScope == "friendsOnly") ? .friendsOnly : .global
        let gkTimeScope: GKLeaderboard.TimeScope
        switch timeScope {
        case "today":
            gkTimeScope = .today
        case "week":
            gkTimeScope = .week
        default:
            gkTimeScope = .allTime
        }
        
        // Load the leaderboard
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, error in
            guard error == nil, let leaderboard = leaderboards?.first else {
                self.leaderboardEntriesLoadFail.emit(
                    (error as NSError?)?.code ?? GameCenterError.unknownError.rawValue,
                    error?.localizedDescription ?? "Failed to load leaderboard",
                    leaderboardID
                )
                return
            }
            
            // Load entries for the specified range
            let range = NSRange(location: rankMin, length: rankMax - rankMin + 1)
            leaderboard.loadEntries(
                for: gkPlayerScope,
                timeScope: gkTimeScope,
                range: range
            ) { localPlayerEntry, entries, totalPlayerCount, error in
                guard error == nil else {
                    self.leaderboardEntriesLoadFail.emit(
                        (error! as NSError).code,
                        "Error loading leaderboard entries",
                        leaderboardID
                    )
                    return
                }
                
                // Convert entries to Godot objects
                var leaderboardEntries = ObjectCollection<GameCenterLeaderboardEntry>()
                if let entries = entries {
                    for entry in entries {
                        leaderboardEntries.append(GameCenterLeaderboardEntry(entry))
                    }
                }
                
                self.leaderboardEntriesLoadSuccess.emit(leaderboardEntries, totalPlayerCount, leaderboardID)
            }
        }
    }

    func loadPlayerScoreInternal(
        leaderboardID: String,
        timeScope: String
    ) {
        guard GKLocalPlayer.local.isAuthenticated == true else {
            self.leaderboardPlayerScoreLoadFail.emit(
                GameCenterError.notAuthenticated.rawValue,
                "Player is not authenticated",
                leaderboardID)
            return
        }
        
        // Convert string parameter to enum
        let gkTimeScope: GKLeaderboard.TimeScope
        switch timeScope {
        case "today":
            gkTimeScope = .today
        case "week":
            gkTimeScope = .week
        default:
            gkTimeScope = .allTime
        }
        
        // Load the leaderboard
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { leaderboards, error in
            guard error == nil, let leaderboard = leaderboards?.first else {
                self.leaderboardPlayerScoreLoadFail.emit(
                    (error as NSError?)?.code ?? GameCenterError.unknownError.rawValue,
                    error?.localizedDescription ?? "Failed to load leaderboard",
                    leaderboardID
                )
                return
            }
            
            // Load just the player's entry
            leaderboard.loadEntries(
                for: .global,
                timeScope: gkTimeScope,
                range: NSRange(location: 1, length: 1)
            ) { localPlayerEntry, entries, totalPlayerCount, error in
                guard error == nil else {
                    self.leaderboardPlayerScoreLoadFail.emit(
                        (error! as NSError).code,
                        "Error loading player score",
                        leaderboardID
                    )
                    return
                }
                
                guard let localPlayerEntry = localPlayerEntry else {
                    self.leaderboardPlayerScoreLoadFail.emit(
                        GameCenterError.unknownError.rawValue,
                        "No score found for player",
                        leaderboardID
                    )
                    return
                }
                
                // Convert to Godot object and emit
                let playerEntry = GameCenterLeaderboardEntry(localPlayerEntry)
                self.leaderboardPlayerScoreLoadSuccess.emit(playerEntry, leaderboardID)
            }
        }
    }
}
