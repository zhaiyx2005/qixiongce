extends Control
class_name CardDecoration

var kind := ""
var accent := Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var ink := Color(accent, 0.13)
	var center := size * Vector2(0.5, 0.43)
	var radius := minf(size.x * 0.34, size.y * 0.27)
	draw_arc(center, radius, 0, TAU, 40, ink, 1.2, true)
	var upper := center + Vector2(0, -radius * 0.8)
	var lower := center + Vector2(0, radius * 0.8)
	match kind:
		CardData.UNIT_ARCHER:
			draw_arc(center, radius * 0.8, -PI * 0.5, PI * 0.5, 24, ink, 2, true)
			draw_line(upper, lower, ink, 1.5, true)
			draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), ink, 2, true)
		CardData.UNIT_CAVALRY:
			draw_line(lower, upper, ink, 2, true)
			draw_colored_polygon(PackedVector2Array([upper, upper + Vector2(radius, radius * 0.4), center]), ink)
		CardData.UNIT_INFANTRY:
			draw_line(upper + Vector2(-radius * 0.5, 0), lower + Vector2(radius * 0.5, 0), ink, 2, true)
			draw_line(upper + Vector2(radius * 0.5, 0), lower + Vector2(-radius * 0.5, 0), ink, 2, true)
		_:
			draw_polyline(PackedVector2Array([upper, center + Vector2(radius * 0.65, 0), lower, center - Vector2(radius * 0.65, 0), upper]), ink, 2, true)
	var edge := Color(accent, 0.32)
	for x in [6.0, size.x - 6.0]:
		var direction := 1.0 if x < size.x * 0.5 else -1.0
		draw_line(Vector2(x, 6), Vector2(x + 9 * direction, 6), edge, 1, true)
		draw_line(Vector2(x, 6), Vector2(x, 14), edge, 1, true)
