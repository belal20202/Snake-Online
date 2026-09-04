extends Node

var player_name: String = "لاعب"

var coins: int = 0
var experience: int = 0
var level: int = 1

var last_score: int = 0
var last_length: int = 10


func reset_match_stats() -> void:
	last_score = 0
	last_length = 10
