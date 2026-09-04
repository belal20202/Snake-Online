extends Node

# =========================================================
# 🐍 SNAKE ARAB ONLINE
# النظام العام للاعب
# الخطوة 6.3
# =========================================================

# =========================================================
# بيانات اللاعب
# =========================================================

var player_name: String = ""

var coins: int = 0

var experience: int = 0

var level: int = 1

# =========================================================
# إحصائيات الجولة الأخيرة
# =========================================================

var last_score: int = 0

var last_coins: int = 0

var last_length: int = 0

# =========================================================
# ملف الحفظ
# =========================================================

const SAVE_PATH := "user://snake_arab_save.json"


# =========================================================
# البداية
# =========================================================

func _ready() -> void:

	load_data()


# =========================================================
# إضافة عملات
# =========================================================

func add_coins(amount: int) -> void:

	if amount <= 0:
		return

	coins += amount

	save_data()


# =========================================================
# خصم العملات
# =========================================================

func spend_coins(amount: int) -> bool:

	if amount <= 0:
		return true

	if coins < amount:
		return false

	coins -= amount

	save_data()

	return true


# =========================================================
# التحقق من امتلاك العملات
# =========================================================

func has_coins(amount: int) -> bool:

	return coins >= amount


# =========================================================
# إضافة خبرة
# =========================================================

func add_experience(amount: int) -> void:

	if amount <= 0:
		return

	experience += amount

	_check_level_up()

	save_data()


# =========================================================
# حساب مستوى اللاعب
# =========================================================

func _check_level_up() -> void:

	var required_experience := level * 100

	while experience >= required_experience:

		experience -= required_experience

		level += 1

		required_experience = level * 100


# =========================================================
# حفظ البيانات
# =========================================================

func save_data() -> void:

	var data := {
		"player_name": player_name,
		"coins": coins,
		"experience": experience,
		"level": level
	}

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		return

	file.store_string(
		JSON.stringify(data)
	)

	file.close()


# =========================================================
# تحميل البيانات
# =========================================================

func load_data() -> void:

	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
	)

	if file == null:
		return

	var content := file.get_as_text()

	file.close()

	if content.is_empty():
		return

	var json := JSON.new()

	var result := json.parse(content)

	if result != OK:
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		return


	if data.has("player_name"):
		player_name = str(
			data["player_name"]
		)


	if data.has("coins"):
		coins = max(
			0,
			int(data["coins"])
		)


	if data.has("experience"):
		experience = max(
			0,
			int(data["experience"])
		)


	if data.has("level"):
		level = max(
			1,
			int(data["level"])
		)


# =========================================================
# تصفير بيانات اللاعب
# =========================================================

func reset_data() -> void:

	player_name = ""

	coins = 0

	experience = 0

	level = 1

	last_score = 0

	last_coins = 0

	last_length = 0

	save_data()
