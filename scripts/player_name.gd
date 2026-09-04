extends Control


func _ready() -> void:
	$CenterContainer/VBoxContainer/NameEdit.grab_focus()


func _on_continue_button_pressed() -> void:
	var player_name := $CenterContainer/VBoxContainer/NameEdit.text.strip_edges()

	if player_name.length() < 2:
		$CenterContainer/VBoxContainer/Message.text = "اكتب اسمًا من حرفين على الأقل"
		return

	if player_name.length() > 16:
		$CenterContainer/VBoxContainer/Message.text = "الاسم يجب ألا يتجاوز 16 حرفًا"
		return

	Global.player_name = player_name
	Global.reset_match_stats()

	get_tree().change_scene_to_file(
		"res://scenes/lobby.tscn"
	)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(
		"res://scenes/main_menu.tscn"
	)
