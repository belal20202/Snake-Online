extends Node2D

var snake_scene := preload("res://scenes/snake.tscn")
var remote_snake_script := preload("res://scripts/remote_snake.gd")

var local_snake: Node2D
var camera: Camera2D

var remote_snakes: Dictionary = {}
var network_foods: Dictionary = {}
var network_loot: Dictionary = {}

var score := 0
var kills := 0
var deaths := 0

var paused := false
var game_over := false

var state_timer := 0.0
var notification_timer := 0.0

var leaderboard_data: Array = []

var score_label: Label
var length_label: Label
var players_label: Label
var kills_label: Label
var deaths_label: Label
var rank_label: Label

var leaderboard_panel: Panel
var leaderboard_container: VBoxContainer

var notification_label: Label

var game_ui: CanvasLayer


func _ready() -> void:
	add_to_group("game")

	_create_background()
	_create_local_player()
	_create_ui()
	_connect_network()


# =========================================================
# BACKGROUND
# =========================================================

func _create_background() -> void:
	var background := ColorRect.new()

	background.position = Vector2(
		-3000,
		-3000
	)

	background.size = Vector2(
		6000,
		6000
	)

	background.color = Color(
		0.035,
		0.055,
		0.07,
		1.0
	)

	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(background)
	move_child(background, 0)


# =========================================================
# LOCAL PLAYER
# =========================================================

func _create_local_player() -> void:
	local_snake = snake_scene.instantiate()

	add_child(local_snake)

	var spawn_position := Vector2.ZERO

	if Network.is_host:
		var local_data := Network.get_local_player()

		if not local_data.is_empty():
			spawn_position = local_data.get(
				"position",
				Vector2.ZERO
			)

	local_snake.position = spawn_position

	if local_snake.has_method("setup"):
		local_snake.setup(
			Global.player_name
		)

	_create_camera()


func _create_camera() -> void:
	camera = Camera2D.new()

	camera.position = Vector2.ZERO

	camera.limit_left = int(-2000)
	camera.limit_right = int(2000)
	camera.limit_top = int(-2000)
	camera.limit_bottom = int(2000)

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0

	local_snake.add_child(camera)


# =========================================================
# UI
# =========================================================

func _create_ui() -> void:
	game_ui = CanvasLayer.new()
	add_child(game_ui)

	var top_bar := Panel.new()

	top_bar.position = Vector2(20, 20)
	top_bar.size = Vector2(1240, 70)

	game_ui.add_child(top_bar)

	score_label = _create_label(
		"النتيجة: 0",
		Vector2(25, 18),
		Vector2(180, 35),
		20
	)

	length_label = _create_label(
		"الطول: 10",
		Vector2(220, 18),
		Vector2(180, 35),
		20
	)

	kills_label = _create_label(
		"القتلات: 0",
		Vector2(420, 18),
		Vector2(150, 35),
		20
	)

	deaths_label = _create_label(
		"الوفيات: 0",
		Vector2(580, 18),
		Vector2(150, 35),
		20
	)

	players_label = _create_label(
		"اللاعبون: 1",
		Vector2(740, 18),
		Vector2(170, 35),
		20
	)

	rank_label = _create_label(
		"الترتيب: 1",
		Vector2(920, 18),
		Vector2(180, 35),
		20
	)

	top_bar.add_child(score_label)
	top_bar.add_child(length_label)
	top_bar.add_child(kills_label)
	top_bar.add_child(deaths_label)
	top_bar.add_child(players_label)
	top_bar.add_child(rank_label)

	_create_leaderboard()

	notification_label = _create_label(
		"",
		Vector2(390, 105),
		Vector2(500, 50),
		24
	)

	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	game_ui.add_child(notification_label)


func _create_label(
	text_value: String,
	position_value: Vector2,
	size_value: Vector2,
	font_size: int
) -> Label:

	var label := Label.new()

	label.text = text_value
	label.position = position_value
	label.size = size_value

	label.add_theme_font_size_override(
		"font_size",
		font_size
	)

	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	return label


# =========================================================
# LEADERBOARD UI
# =========================================================

func _create_leaderboard() -> void:
	leaderboard_panel = Panel.new()

	leaderboard_panel.position = Vector2(
		940,
		110
	)

	leaderboard_panel.size = Vector2(
		320,
		360
	)

	game_ui.add_child(leaderboard_panel)

	var title := Label.new()

	title.text = "🏆 المتصدرون"

	title.position = Vector2(
		15,
		10
	)

	title.size = Vector2(
		290,
		40
	)

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	title.add_theme_font_size_override(
		"font_size",
		24
	)

	leaderboard_panel.add_child(title)

	leaderboard_container = VBoxContainer.new()

	leaderboard_container.position = Vector2(
		15,
		55
	)

	leaderboard_container.size = Vector2(
		290,
		280
	)

	leaderboard_container.add_theme_constant_override(
		"separation",
		6
	)

	leaderboard_panel.add_child(
		leaderboard_container
	)


func _update_leaderboard() -> void:
	if leaderboard_container == null:
		return

	for child in leaderboard_container.get_children():
		child.queue_free()

	var max_entries := min(
		5,
		leaderboard_data.size()
	)

	for i in range(max_entries):
		var entry: Dictionary = leaderboard_data[i]

		var row := Label.new()

		var rank := int(entry.get("rank", i + 1))
		var name := str(entry.get("name", "لاعب"))
		var length := int(entry.get("length", 10))
		var player_kills := int(entry.get("kills", 0))
		var player_id := int(entry.get("id", 0))

		var crown := ""

		if rank == 1:
			crown = "👑 "

		row.text = (
			crown
			+ str(rank)
			+ ". "
			+ name
			+ "   "
			+ str(length)
		)

		if player_id == Network.local_player_id:
			row.text = "⭐ " + row.text

		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		row.add_theme_font_size_override(
			"font_size",
			18
		)

		leaderboard_container.add_child(row)

	# عرض اللاعب المحلي إذا كان خارج أول 5
	var local_rank := Network.get_player_rank(
		Network.local_player_id
	)

	if local_rank > 5:
		var separator := Label.new()

		separator.text = "────────────"

		separator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		leaderboard_container.add_child(
			separator
		)

		var local_entry := _find_local_leaderboard_entry()

		if not local_entry.is_empty():
			var local_row := Label.new()

			local_row.text = (
				"⭐ "
				+ str(local_rank)
				+ ". "
				+ str(local_entry.get("name", "أنت"))
				+ "   "
				+ str(local_entry.get("length", 10))
			)

			local_row.add_theme_font_size_override(
				"font_size",
				18
			)

			leaderboard_container.add_child(
				local_row
			)


func _find_local_leaderboard_entry() -> Dictionary:
	for entry in leaderboard_data:
		if int(entry.get("id", 0)) == Network.local_player_id:
			return entry

	return {}


# =========================================================
# NETWORK
# =========================================================

func _connect_network() -> void:
	Network.players_synced_signal.connect(
		_on_players_synced
	)

	Network.player_died_signal.connect(
		_on_player_died
	)

	Network.player_respawned_signal.connect(
		_on_player_respawned
	)

	Network.leaderboard_updated_signal.connect(
		_on_leaderboard_updated
	)

	Network.food_spawned_signal.connect(
		_on_food_spawned
	)

	Network.food_collected_signal.connect(
		_on_food_collected
	)

	Network.loot_spawned_signal.connect(
		_on_loot_spawned
	)

	Network.loot_collected_signal.connect(
		_on_loot_collected
	)


# =========================================================
# PROCESS
# =========================================================

func _process(delta: float) -> void:
	if paused:
		return

	state_timer += delta

	if state_timer >= 0.05:
		state_timer = 0.0
		_send_local_state()

	_update_camera()
	_update_ui()

	if notification_timer > 0.0:
		notification_timer -= delta

		if notification_timer <= 0.0:
			notification_label.text = ""


func _send_local_state() -> void:
	if local_snake == null:
		return

	if not is_instance_valid(local_snake):
		return

	var direction := Vector2.RIGHT

	if local_snake.has_method("get_direction"):
		direction = local_snake.get_direction()

	var length := 10

	if local_snake.has_method("get_length"):
		length = local_snake.get_length()

	var alive := true

	if local_snake.has_method("is_snake_dead"):
		alive = not local_snake.is_snake_dead()

	Network.broadcast_player_state(
		local_snake.global_position,
		direction,
		length,
		alive
	)


# =========================================================
# PLAYER SYNC
# =========================================================

func _on_players_synced(snapshot: Dictionary) -> void:
	_update_remote_snakes(snapshot)
	_update_local_stats(snapshot)


func _update_local_stats(snapshot: Dictionary) -> void:
	if not snapshot.has(Network.local_player_id):
		return

	var data: Dictionary = snapshot[
		Network.local_player_id
	]

	kills = int(data.get("kills", 0))
	deaths = int(data.get("deaths", 0))

	_update_leaderboard()


func _update_remote_snakes(snapshot: Dictionary) -> void:
	for id in snapshot:
		var peer_id := int(id)

		if peer_id == Network.local_player_id:
			continue

		var data: Dictionary = snapshot[id]

		_create_or_update_remote_snake(
			peer_id,
			data
		)

	var existing_ids := remote_snakes.keys()

	for id in existing_ids:
		if not snapshot.has(id):
			_remove_remote_snake(id)


func _create_or_update_remote_snake(
	peer_id: int,
	data: Dictionary
) -> void:

	var player_name := str(
		data.get("name", "لاعب")
	)

	var position_value: Vector2 = data.get(
		"position",
		Vector2.ZERO
	)

	var direction_value: Vector2 = data.get(
		"direction",
		Vector2.RIGHT
	)

	var length_value := int(
		data.get("length", 10)
	)

	var alive_value := bool(
		data.get("alive", true)
	)

	if not remote_snakes.has(peer_id):
		_create_remote_snake(
			peer_id,
			player_name,
			position_value
		)

	if not remote_snakes.has(peer_id):
		return

	var remote = remote_snakes[peer_id]

	if not is_instance_valid(remote):
		remote_snakes.erase(peer_id)

		_create_remote_snake(
			peer_id,
			player_name,
			position_value
		)

		return

	if remote.has_method("set_player_name"):
		remote.set_player_name(
			player_name
		)

	if remote.has_method("update_state"):
		remote.update_state(
			position_value,
			direction_value,
			length_value,
			alive_value
		)


func _create_remote_snake(
	peer_id: int,
	player_name: String,
	start_position: Vector2
) -> void:

	var remote := Node2D.new()

	remote.set_script(
		remote_snake_script
	)

	add_child(remote)

	remote.position = start_position

	if remote.has_method("setup"):
		remote.setup(
			peer_id,
			player_name,
			start_position
		)

	remote_snakes[peer_id] = remote


func _remove_remote_snake(peer_id: int) -> void:
	if not remote_snakes.has(peer_id):
		return

	var remote = remote_snakes[peer_id]

	if is_instance_valid(remote):
		remote.queue_free()

	remote_snakes.erase(peer_id)


# =========================================================
# DEATH
# =========================================================

func _on_player_died(
	victim_id: int,
	killer_id: int,
	death_position: Vector2,
	reward: Dictionary
) -> void:

	if victim_id == Network.local_player_id:
		game_over = true

		var killer_name := "لاعب"

		if Network.players.has(killer_id):
			killer_name = str(
				Network.players[killer_id].get(
					"name",
					"لاعب"
				)
			)

		if killer_id != 0:
			_show_notification(
				"💀 تم القضاء عليك بواسطة "
				+ killer_name
			)
		else:
			_show_notification(
				"💀 لقد خسرت!"
			)

	else:
		if remote_snakes.has(victim_id):
			var remote = remote_snakes[victim_id]

			if is_instance_valid(remote):
				if remote.has_method("die"):
					remote.die()

		if killer_id == Network.local_player_id:
			var coins := int(
				reward.get("coins", 0)
			)

			_show_notification(
				"🏆 قضيت على لاعب! +"
				+ str(coins)
				+ " عملة"
			)


# =========================================================
# RESPAWN
# =========================================================

func _on_player_respawned(
	peer_id: int,
	spawn_position: Vector2
) -> void:

	if peer_id == Network.local_player_id:
		game_over = false

		if local_snake != null:
			local_snake.global_position = spawn_position

			if local_snake.has_method("revive"):
				local_snake.revive()

			if local_snake.has_method("reset"):
				local_snake.reset()

	else:
		if remote_snakes.has(peer_id):
			var remote = remote_snakes[peer_id]

			if is_instance_valid(remote):
				if remote.has_method("respawn"):
					remote.respawn(
						spawn_position
					)


# =========================================================
# LEADERBOARD
# =========================================================

func _on_leaderboard_updated(
	new_leaderboard: Array
) -> void:

	leaderboard_data = new_leaderboard

	_update_leaderboard()

	_update_rank_label()


func _update_rank_label() -> void:
	var local_rank := 0

	for entry in leaderboard_data:
		if int(entry.get("id", 0)) == Network.local_player_id:
			local_rank = int(
				entry.get("rank", 0)
			)
			break

	if local_rank <= 0:
		local_rank = Network.get_player_rank(
			Network.local_player_id
		)

	rank_label.text = (
		"الترتيب: "
		+ str(local_rank)
	)


# =========================================================
# UI UPDATE
# =========================================================

func _update_ui() -> void:
	if local_snake == null:
		return

	var current_length := 10

	if local_snake.has_method("get_length"):
		current_length = local_snake.get_length()

	score_label.text = (
		"النتيجة: "
		+ str(score)
	)

	length_label.text = (
		"الطول: "
		+ str(current_length)
	)

	kills_label.text = (
		"القتلات: "
		+ str(kills)
	)

	deaths_label.text = (
		"الوفيات: "
		+ str(deaths)
	)

	players_label.text = (
		"اللاعبون: "
		+ str(Network.get_player_count())
	)

	_update_rank_label()


func _update_camera() -> void:
	if camera == null:
		return

	if local_snake == null:
		return

	if not is_instance_valid(local_snake):
		return

	camera.position = Vector2.ZERO


# =========================================================
# FOOD
# =========================================================

func _on_food_spawned(
	food_id: int,
	position_value: Vector2,
	value: int
) -> void:

	network_foods[food_id] = {
		"position": position_value,
		"value": value
	}


func _on_food_collected(
	food_id: int,
	collector_id: int,
	value: int
) -> void:

	network_foods.erase(food_id)

	if collector_id == Network.local_player_id:
		score += value

		if local_snake != null:
			if local_snake.has_method("grow"):
				local_snake.grow(value)


# =========================================================
# LOOT
# =========================================================

func _on_loot_spawned(
	loot_id: int,
	position_value: Vector2,
	coins: int,
	xp: int
) -> void:

	network_loot[loot_id] = {
		"position": position_value,
		"coins": coins,
		"xp": xp
	}


func _on_loot_collected(
	loot_id: int,
	collector_id: int,
	coins: int,
	xp: int
) -> void:

	network_loot.erase(loot_id)

	if collector_id == Network.local_player_id:
		score += coins


# =========================================================
# NOTIFICATION
# =========================================================

func _show_notification(
	text_value: String
) -> void:

	notification_label.text = text_value
	notification_timer = 3.0


# =========================================================
# GAME CONTROL
# =========================================================

func pause_game() -> void:
	paused = true
	get_tree().paused = true


func resume_game() -> void:
	paused = false
	get_tree().paused = false


func request_respawn() -> void:
	game_over = false
	Network.request_respawn()


func get_current_rank() -> int:
	for entry in leaderboard_data:
		if int(entry.get("id", 0)) == Network.local_player_id:
			return int(entry.get("rank", 0))

	return 0
