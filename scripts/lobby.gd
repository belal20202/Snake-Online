extends Control

@onready var status_label: Label = $Panel/VBox/Status
@onready var players_label: Label = $Panel/VBox/Players
@onready var ip_edit: LineEdit = $Panel/VBox/IP
@onready var host_button: Button = $Panel/VBox/HostButton
@onready var join_button: Button = $Panel/VBox/JoinButton
@onready var start_button: Button = $Panel/VBox/StartButton
@onready var back_button: Button = $Panel/VBox/BackButton

var network: Node


func _ready() -> void:
	network = get_node_or_null("/root/Network")

	if network == null:
		network = load("res://scripts/network.gd").new()
		network.name = "Network"
		get_tree().root.add_child(network)

	network.connected_to_server.connect(_on_connected)
	network.connection_failed.connect(_on_connection_failed)
	network.player_connected.connect(_on_player_changed)
	network.player_disconnected.connect(_on_player_changed)

	start_button.disabled = true

	_update_ui()

	$Panel/VBox/IP.grab_focus()


func _process(_delta: float) -> void:
	_update_ui()


func _update_ui() -> void:
	if network == null:
		return

	var count := network.get_player_count()

	if multiplayer.multiplayer_peer == null:
		players_label.text = "اللاعبون: 0 / 16"

	else:
		players_label.text = "اللاعبون: %d / 16" % count

	if network.is_host:
		status_label.text = "أنت المضيف — بانتظار اللاعبين"
		start_button.disabled = count < 1
	elif multiplayer.multiplayer_peer:
		status_label.text = "متصل بالغرفة"


func _on_host_button_pressed() -> void:
	var success: bool = network.host_game()

	if success:
		status_label.text = "تم إنشاء الغرفة بنجاح"
		host_button.disabled = true
		join_button.disabled = true
		start_button.disabled = false
	else:
		status_label.text = "تعذر إنشاء الغرفة"


func _on_join_button_pressed() -> void:
	var ip := ip_edit.text.strip_edges()

	if ip.is_empty():
		status_label.text = "اكتب عنوان IP أولًا"
		return

	var success: bool = network.join_game(ip)

	if success:
		status_label.text = "جاري الاتصال..."
		host_button.disabled = true
		join_button.disabled = true
	else:
		status_label.text = "تعذر بدء الاتصال"


func _on_connected() -> void:
	status_label.text = "تم الاتصال بالمضيف"
	start_button.disabled = true


func _on_connection_failed() -> void:
	status_label.text = "فشل الاتصال بالغرفة"

	host_button.disabled = false
	join_button.disabled = false


func _on_player_changed(_peer_id: int) -> void:
	_update_ui()


func _on_start_button_pressed() -> void:
	if not network.is_host:
		return

	var count := network.get_player_count()

	if count < 1:
		status_label.text = "لا يوجد لاعبون"
		return

	_start_game.rpc()


@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_back_button_pressed() -> void:
	network.close_connection()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
