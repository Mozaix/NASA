class_name Classroom
extends RefCounted
## Classroom mode: a teacher names a class (for example "Class 6B") before the lesson, and every result
## played on this computer is also counted for that class. Totals only, no player names, nothing leaves
## the computer. Results live in user:// next to the all-time totals.

## Tests point this somewhere else so they never touch real results.
static var root := "user://"

static func _index_path() -> String:
	return root + "classroom.json"

static func load_index() -> Dictionary:
	var d := {"active": "", "classes": []}
	if not FileAccess.file_exists(_index_path()):
		return d
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(_index_path())) != OK or not json.data is Dictionary:
		return d
	var data: Dictionary = json.data
	if data.get("active") is String:
		d.active = data.active
	if data.get("classes") is Array:
		d.classes = (data.classes as Array).filter(func(c: Variant) -> bool: return c is String and c != "")
	return d

static func _save_index(d: Dictionary) -> void:
	var f := FileAccess.open(_index_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

## The class currently being taught, or "" when none is running.
static func active() -> String:
	return str(load_index().active)

static func classes() -> Array:
	return load_index().classes

static func clean_name(class_name_text: String) -> String:
	return class_name_text.strip_edges().left(40)

static func start_class(class_name_text: String) -> String:
	var n := clean_name(class_name_text)
	if n == "":
		return ""
	var d := load_index()
	if not (d.classes as Array).has(n):
		(d.classes as Array).append(n)
	d.active = n
	_save_index(d)
	return n

static func end_class() -> void:
	var d := load_index()
	d.active = ""
	_save_index(d)

## Removes a class and its results. The all-time totals keep them.
static func delete_class(class_name_text: String) -> void:
	var d := load_index()
	(d.classes as Array).erase(class_name_text)
	if d.active == class_name_text:
		d.active = ""
	_save_index(d)
	for p: String in [quiz_path(class_name_text), debris_path(class_name_text)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func _slug(class_name_text: String) -> String:
	var out := ""
	for ch in class_name_text.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	# Two names that clean to the same letters (or Arabic names) still get their own files.
	return "%s_%08x" % [out.left(24), class_name_text.hash() & 0xffffffff]

## Quiz totals for one class, or the all-time totals for "".
static func quiz_path(class_name_text: String) -> String:
	if class_name_text == "":
		return root + "quiz_results.json" if root != "user://" else QuizScene.RESULTS_PATH
	return root + "class_%s_quiz.json" % _slug(class_name_text)

static func debris_path(class_name_text: String) -> String:
	if class_name_text == "":
		return root + "debris_stats.json"
	return root + "class_%s_debris.json" % _slug(class_name_text)

## Called when a demo player finishes both quizzes. The all-time totals are recorded by the quiz itself.
static func record_quiz(before: int, after: int, before_right: Array, after_right: Array) -> void:
	var a := active()
	if a != "":
		QuizScene.record(before, after, quiz_path(a), before_right, after_right)

## {question id: {q, asked, right}} for one class, or all-time for "".
static func load_debris(class_name_text: String) -> Dictionary:
	var p := debris_path(class_name_text)
	if not FileAccess.file_exists(p):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK or not json.data is Dictionary:
		return {}
	return json.data

## One answer in the debris dodge, counted all-time and for the running class.
static func record_debris(q: Dictionary, right: bool) -> void:
	var names := [""]
	var a := active()
	if a != "":
		names.append(a)
	for n: String in names:
		var d := load_debris(n)
		var key := str(q.get("id", "?"))
		var e: Dictionary = d.get(key, {"q": str(q.get("q", "")), "asked": 0, "right": 0})
		e.q = str(q.get("q", e.get("q", "")))
		e.asked = int(e.get("asked", 0)) + 1
		e.right = int(e.get("right", 0)) + (1 if right else 0)
		d[key] = e
		var f := FileAccess.open(debris_path(n), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(d))

## Debris questions as rows sorted hardest first: [{id, q, asked, right, share}].
static func debris_rows(class_name_text: String) -> Array:
	var d := load_debris(class_name_text)
	var rows: Array = []
	for k: String in d:
		var e: Dictionary = d[k]
		var asked := int(e.get("asked", 0))
		if asked > 0:
			rows.append({"id": k, "q": str(e.get("q", "")), "asked": asked, "right": int(e.get("right", 0)), "share": float(e.get("right", 0)) / asked})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.share) < float(y.share))
	return rows
