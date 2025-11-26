[![Godot](https://img.shields.io/badge/Godot%20Engine-4.3-blue.svg)](https://github.com/godotengine/godot/)
[![SwiftGodot](https://img.shields.io/badge/SwiftGodot-main-blue.svg)](https://github.com/migueldeicaza/SwiftGodot/)
![Platforms](https://img.shields.io/badge/platforms-iOS-333333.svg?style=flat)
![iOS](https://img.shields.io/badge/iOS-17+-green.svg?style=flat)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg?maxAge=2592000)](https://github.com/zt-pawer/SwiftGodotGameCenter/blob/main/LICENSE)

# Development status
Initial effort focused on bringing this GDExtension implementation to parity with [Godot Gamecenter Ios Plugin](https://github.com/godot-sdk-integrations/godot-ios-plugins/tree/master/plugins/gamecenter).

This fork adds programmatic leaderboard data retrieval, enabling developers to display player ranks and scores within their games without relying solely on the native GameCenter UI.

# How to use it
See Godot demo project for an end to end implementation.
Register all the signals required, this can be done in the ``_ready()`` method and connect each signal to the relative method.
```gdscript
func _ready() -> void:
    if _gamecenter == null && ClassDB.class_exists("GameCenter"):
        _gamecenter = ClassDB.instantiate("GameCenter")
        
        # Authentication
        _gamecenter.signin_success.connect(_on_signin_success)
        _gamecenter.signin_fail.connect(_on_signin_fail)
        
        # Achievements
        _gamecenter.achievements_description_success.connect(_on_achievements_description_success)
        _gamecenter.achievements_description_fail.connect(_on_achievements_description_fail)
        _gamecenter.achievements_report_success.connect(_on_achievements_report_success)
        _gamecenter.achievements_report_fail.connect(_on_achievements_report_fail)
        _gamecenter.achievements_load_success.connect(_on_achievements_load_success)
        _gamecenter.achievements_load_fail.connect(_on_achievements_load_fail)
        _gamecenter.achievements_reset_success.connect(_on_achievements_reset_success)
        _gamecenter.achievements_reset_fail.connect(_on_achievements_reset_fail)
        
        # Leaderboard UI
        _gamecenter.leaderboard_success.connect(_on_leaderboard_success)
        _gamecenter.leaderboard_dismissed.connect(_on_leaderboard_dismissed)
        _gamecenter.leaderboard_fail.connect(_on_leaderboard_fail)
        
        # Leaderboard Score Submission (use NEW signals for leaderboard ID tracking)
        _gamecenter.leaderboard_score_ingame_success.connect(_on_leaderboard_score_success)
        _gamecenter.leaderboard_score_ingame_fail.connect(_on_leaderboard_score_fail)
        
        # Leaderboard Data Retrieval (NEW)
        _gamecenter.leaderboard_entries_load_success.connect(_on_leaderboard_entries_load_success)
        _gamecenter.leaderboard_entries_load_fail.connect(_on_leaderboard_entries_load_fail)
        _gamecenter.leaderboard_player_score_load_success.connect(_on_leaderboard_player_score_load_success)
        _gamecenter.leaderboard_player_score_load_fail.connect(_on_leaderboard_player_score_load_fail)
```

## Callback Method Signatures
```gdscript
# Authentication
func _on_signin_fail(error: int, message: String) -> void:
func _on_signin_success(player: GameCenterPlayerLocal) -> void:

# Achievements
func _on_achievements_description_fail(error: int, message: String) -> void:
func _on_achievements_description_success(achievements: Array[GameCenterAchievementDescription]) -> void:
func _on_achievements_report_fail(error: int, message: String) -> void:
func _on_achievements_report_success() -> void:
func _on_achievements_load_fail(error: int, message: String) -> void:
func _on_achievements_load_success(achievements: Array[GameCenterAchievement]) -> void:
func _on_achievements_reset_fail(error: int, message: String) -> void:
func _on_achievements_reset_success() -> void:

# Leaderboard UI
func _on_leaderboard_dismissed() -> void:
func _on_leaderboard_success() -> void:
func _on_leaderboard_fail(error: int, message: String) -> void:

# Leaderboard Score Submission (backwards compatible - old signals still work)
func _on_leaderboard_score_success() -> void:  # Old signal - no leaderboard ID
func _on_leaderboard_score_fail(error: int, message: String) -> void:  # Old signal - no leaderboard ID

# Leaderboard Score Submission (NEW - with leaderboard ID tracking)
func _on_leaderboard_score_success(leaderboard_id: String) -> void:  # NEW signal
func _on_leaderboard_score_fail(error: int, message: String, leaderboard_id: String) -> void:  # NEW signal

# Leaderboard Data Retrieval (NEW)
func _on_leaderboard_entries_load_success(entries: Array[GameCenterLeaderboardEntry], total_player_count: int, leaderboard_id: String) -> void:
func _on_leaderboard_entries_load_fail(error: int, message: String, leaderboard_id: String) -> void:
func _on_leaderboard_player_score_load_success(entry: GameCenterLeaderboardEntry, leaderboard_id: String) -> void:
func _on_leaderboard_player_score_load_fail(error: int, message: String, leaderboard_id: String) -> void:
```

# Technical details

## Signals

### Authorization
- `signin_success` SignalWithArguments<GameCenterPlayerLocal>
- `signin_fail` SignalWithArguments<Int,String>

### Achievements
- `achievements_description_success` SignalWithArguments<[GameCenterAchievementDescription]>
- `achievements_description_fail` SignalWithArguments<Int,String>
- `achievements_report_success` SimpleSignal
- `achievements_report_fail` SignalWithArguments<Int,String>
- `achievements_load_success` SignalWithArguments<[GameCenterAchievement]>
- `achievements_load_fail` SignalWithArguments<Int,String>
- `achievements_reset_success` SimpleSignal
- `achievements_reset_fail` SignalWithArguments<Int,String>

### Leaderboards - UI
- `leaderboard_success` SimpleSignal
- `leaderboard_dismissed` SimpleSignal
- `leaderboard_fail` SignalWithArguments<Int,String>

### Leaderboards - Score Submission
**Legacy:**
- `leaderboard_score_success` SimpleSignal - no leaderboard ID
- `leaderboard_score_fail` SignalWithArguments<Int,String> - no leaderboard ID
**New:**
- `leaderboard_score_ingame_success` SignalWithArguments<String> - includes leaderboard ID
- `leaderboard_score_ingame_fail` SignalWithArguments<Int,String,String> - includes leaderboard ID

### Leaderboards - Data Retrieval
- `leaderboard_entries_load_success` SignalWithArguments<[GameCenterLeaderboardEntry],Int,String> - entries, total player count, leaderboard ID
- `leaderboard_entries_load_fail` SignalWithArguments<Int,String,String> - error, message, leaderboard ID
- `leaderboard_player_score_load_success` SignalWithArguments<GameCenterLeaderboardEntry,String> - player's entry, leaderboard ID
- `leaderboard_player_score_load_fail` SignalWithArguments<Int,String,String> - error, message, leaderboard ID

## Methods

### Authorization
- `authenticate()` - Performs user authentication.  
- `isAuthenticated()` - Returns authentication state.  

### Achievements
- `loadAchievementDescriptions()` - Load all achievement descriptions.
- `reportAchievements(achievements: [GameCenterAchievement])` - Report an array of achievements.
- `loadAchievements()` - Load the progress of achievements.
- `resetAchievements()` - Reset the achievements progress for the local player.
- `showAchievements()` - Open GameCenter Achievements UI.
- `showAchievement(achievementID: String)` - Open GameCenter UI for a specific achievement.

### Leaderboards
- `submitScore(score: Int, leaderboardIDs: [String], context: Int)` - Submit a score to one or more leaderboards. Emits both old signals (backwards compatible) and new signals (with leaderboard ID).
- `showLeaderboards()` - Open GameCenter Leaderboards UI.
- `showLeaderboard(leaderboardID: String)` - Open a specific GameCenter Leaderboard UI.
- `loadLeaderboardEntries(leaderboardID: String, playerScope: String, timeScope: String, rankMin: Int, rankMax: Int)` - Load leaderboard entries for a range of ranks. 
- `loadPlayerScore(leaderboardID: String, timeScope: String)` - **NEW** - Load the local player's score and rank regardless of their position on the leaderboard.
