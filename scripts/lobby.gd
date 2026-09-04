extends Control

@onready var status_label: Label = $Panel/VBox/Status
@onready var players_label: Label = $Panel/VBox/Players
@onready var ip_edit: LineEdit = $Panel/VBox/IP

@onready var host_button: Button = $Panel/VBox/HostButton
@onready var join_button: Button = $Panel/VBox/JoinButton
@onready var start_button: Button = $Panel/VBox/StartButton
@onready var back_button: Button = $Panel/VBox/BackButton


func _ready() -> void:

	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	start_button.pressed.connect(_on_start_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

	Network.connected_to_server.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)
	Network.player_connected.connect(_on_player_changed)
	Network.player_disconnected.connect(_on_player_changed)

	start_button.disabled = true

	status_label.text = "أنشئ غرفة أو انضم إلى غرفة"

	_update_players()


func _process(_delta: float) -> void:
	_update_players()


func _update_players() -> void:

	var count := Network.get_player_count()

	if multiplayer.multiplayer_peer == null:
		players_label.text = "اللاعبون: 0 / %d" % Network.MAX_PLAYERS
	else:
		players_label.text = "اللاعبون: %d / %d" % [
			count,
			Network.MAX_PLAYERS
		]


func _on_host_button_pressed() -> void:

	var success := Network.host_game()

	if not success:
		status_label.text = "تعذر إنشاء الغرفة"
		return

	status_label.text = "تم إنشاء الغرفة — أنت المضيف"

	host_button.disabled = true
	join_button.disabled = true
	start_button.disabled = false


func _on_join_button_pressed() -> void:

	var ip := ip_edit.text.strip_edges()

	if ip.is_empty():
		status_label.text = "اكتب عنوان IP للمضيف"
		return

	var success := Network.join_game(ip)

	if not success:
		status_label.text = "تعذر بدء الاتصال"
		return

	status_label.text = "جاري الاتصال بالمضيف..."

	host_button.disabled = true
	join_button.disabled = true
	start_button.disabled = true


func _on_connected() -> void:

	status_label.text = "تم الاتصال بالغرفة بنجاح"

	start_button.disabled = true


func _on_connection_failed() -> void:

	status_label.text = "فشل الاتصال بالغرفة"

	host_button.disabled = false
	join_button.disabled = false
	start_button.disabled = true


func _on_player_changed(_peer_id: int) -> void:

	_update_players()


func _on_start_button_pressed() -> void:

	if not Network.is_host:
		status_label.text = "المضيف فقط يستطيع بدء المباراة"
		return

	start_button.disabled = true

	start_game.rpc()


@rpc("authority", "call_local", "reliable")
func start_game() -> void:

	get_tree().change_scene_to_file(
		"res://scenes/game.tscn"
	)


func _on_back_button_pressed() -> void:

	Network.close_connection()

	get_tree().change_scene_to_file(
		"res://scenes/main_menu.tscn"
	)
