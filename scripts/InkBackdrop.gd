extends Control
class_name InkBackdrop

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.COL_BG)
	# 程序化山峦与铜纹，随窗口缩放，无外部素材依赖。
	for layer in range(3):
		var points := PackedVector2Array([Vector2(0, size.y)])
		for i in range(17):
			var x := size.x * float(i) / 16.0
			var y := size.y * (0.69 + layer * 0.065) + sin(i * 1.7 + layer) * (30 - layer * 6)
			points.append(Vector2(x, y))
		points.append(size)
		draw_colored_polygon(points, Color(0.14 + layer * 0.015, 0.19 + layer * 0.01, 0.21, 0.3))
	var gold := Color(UiKit.COL_GOLD, 0.16)
	draw_rect(Rect2(Vector2(24, 24), size - Vector2(48, 48)), gold, false, 1, true)
	for x in [48.0, size.x - 48.0]:
		draw_line(Vector2(x, 42), Vector2(x, size.y - 42), Color(gold, 0.07), 1, true)
	draw_arc(size * 0.5, minf(size.y * 0.39, size.x * 0.3), 0, TAU, 128, Color(gold, 0.06), 1, true)
