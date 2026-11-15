class_name LessonSheet
extends RefCounted
## A printable lesson plan for teachers, as a self-contained web page: goals, a 40-minute plan, the quiz
## and debris questions with answers, discussion prompts, and this class's results when there are any.

static func _e(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

static func html(class_name_text: String = "") -> String:
	var title := "Next Frontier Explorer: lesson sheet"
	var h := PackedStringArray()
	h.append("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>%s</title>" % title)
	h.append("<style>body{font:15px/1.5 system-ui,-apple-system,'Segoe UI',sans-serif;color:#111;max-width:760px;margin:24px auto;padding:0 16px}"
		+ "h1{font-size:24px;margin:0 0 4px}h2{font-size:17px;margin:22px 0 6px;border-bottom:1px solid #ccc;padding-bottom:3px}"
		+ "table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:5px 8px;text-align:left;vertical-align:top}"
		+ ".muted{color:#555;font-size:13px}.ans{color:#0a6b2f;font-weight:600}li{margin:3px 0}"
		+ "@media print{body{margin:0;max-width:none}h2{break-after:avoid}table,li{break-inside:avoid}.noprint{display:none}}</style></head><body>")
	h.append("<h1>Next Frontier Explorer</h1><p class=\"muted\">Lesson sheet%s · version %s · NASA Space Apps Challenge 2026 · Not endorsed by NASA</p>"
		% ["" if class_name_text == "" else " for " + _e(class_name_text), _e(str(ProjectSettings.get_setting("application/config/version", "")))])
	h.append("<p class=\"noprint\"><button onclick=\"print()\">Print this sheet</button></p>")
	h.append("<h2>Learning goals</h2><ul>"
		+ "<li>Explain why a rocket feels the most stress partway up (Max Q), not on the pad or in space.</li>"
		+ "<li>Explain why missions to other planets can only leave during launch windows.</li>"
		+ "<li>Compare gravity on other worlds with Earth's, and say how it changes what a rover does.</li>"
		+ "<li>Describe space debris and meteoroids, and how spacecraft avoid or survive them.</li></ul>")
	h.append("<h2>40-minute plan</h2><table><tr><th>Time</th><th>What happens</th></tr>"
		+ "<tr><td>0–5 min</td><td>In <b>Results</b>, start a class with your class name. Ask: <i>What would you need to plan to land on Mars?</i></td></tr>"
		+ "<tr><td>5–10 min</td><td>Students start <b>Play Demo</b>. It opens with a 3-question quiz (no score pressure).</td></tr>"
		+ "<tr><td>10–30 min</td><td>Students fly the demo, then the <b>Main Game</b>: plan, launch with the T-minus countdown, dodge debris by answering questions, land, explore real NASA terrain.</td></tr>"
		+ "<tr><td>30–35 min</td><td>The demo ends with the same quiz. Open <b>Results</b> to show the class's before and after.</td></tr>"
		+ "<tr><td>35–40 min</td><td>Discuss the hardest debris questions (Results lists them) using the prompts below.</td></tr></table>")
	h.append("<h2>Demo quiz (asked before and after)</h2><ol>")
	for q: Dictionary in QuizScene.QUESTIONS:
		h.append("<li>%s<br><span class=\"ans\">Answer: %s.</span> <span class=\"muted\">%s</span></li>" % [_e(str(q.q)), _e(str(q.right)), _e(str(q.why))])
	h.append("</ol><h2>Debris dodge questions</h2><p class=\"muted\">Players also get questions about their own mission, worked out from NASA data for the world they chose.</p><ol>")
	for q: Dictionary in Questions.HAZARD:
		h.append("<li>%s<br><span class=\"ans\">Answer: %s.</span> <span class=\"muted\">%s</span></li>" % [_e(str(q.q)), _e(str(q.right)), _e(str(q.why))])
	h.append("</ol><h2>Discussion prompts</h2><ul>"
		+ "<li>Your rocket broke up or survived. What were the speed and the air like at that moment?</li>"
		+ "<li>Why did your trip to your world take the time it did? Would leaving a month later change it?</li>"
		+ "<li>Which world would be easiest to jump on? Which would be hardest to leave, and why?</li>"
		+ "<li>Bahrain launched its first locally built satellite, Al Munther, in 2025. What would Bahrain need to launch from its own spaceport?</li>"
		+ "<li>Who should clean up space debris, and how could it be done?</li></ul>")
	h.append(_results_table(class_name_text))
	h.append("<h2>About the data</h2><p class=\"muted\">Planet values: NASA Planetary Fact Sheet. Orbits: JPL. Terrain: NASA MOLA and LOLA elevation. "
		+ "Launch site: NASA/USGS Landsat and SRTM (heights raised ×5 because Bahrain is nearly flat; the spaceport is a concept). "
		+ "Rocket stress and mission scores are game values. The full list is in the game under Credits.</p></body></html>")
	return "\n".join(h)

static func _results_table(class_name_text: String) -> String:
	var r := QuizScene.load_results(Classroom.quiz_path(class_name_text))
	var rows := Classroom.debris_rows(class_name_text)
	if int(r.runs) == 0 and rows.is_empty():
		return ""
	var out := "<h2>Results%s</h2>" % ("" if class_name_text == "" else " for " + _e(class_name_text))
	var runs := int(r.runs)
	if runs > 0:
		var n := QuizScene.QUESTIONS.size()
		out += "<p>%d players finished both quizzes. Average before: %.1f of %d. Average after: %.1f of %d.</p>" % [runs, float(r.before_total) / runs, n, float(r.after_total) / runs, n]
	if not rows.is_empty():
		out += "<table><tr><th>Debris question (hardest first)</th><th>Right</th></tr>"
		for row: Dictionary in rows:
			out += "<tr><td>%s</td><td>%d%% of %d</td></tr>" % [_e(str(row.q)), int(round(float(row.share) * 100.0)), int(row.asked)]
		out += "</table>"
	return out
