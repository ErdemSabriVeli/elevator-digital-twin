class_name LedDisplay
extends MeshInstance3D

## Gercek asansor gostergesi: kirmizi nokta-matris (dot matrix) LED ekran.
##
## Karakterler 5x7 nokta matrisinden olusur; sol tarafta yon oku, sagda kat
## karakteri gosterilir. Yuzey dokusu calisma aninda uretilir, yalnizca icerik
## degistiginde yeniden cizilir.

const CELL := 8                       # bir LED hucresinin piksel boyu
const DOT_R := 3.1                    # LED yaricapi (piksel)
const COLS := 11                      # 5 (ok) + 1 bosluk + 5 (karakter)
const ROWS := 7

const C_ON    := Color(1.00, 0.09, 0.03)
const C_DIM   := Color(0.085, 0.012, 0.008)
const C_BG    := Color(0.020, 0.018, 0.020)

# 5x7 nokta matris font
const FONT := {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}

const ARROW_UP := ["00100", "01110", "11111", "00100", "00100", "00100", "00100"]
const ARROW_DN := ["00100", "00100", "00100", "00100", "11111", "01110", "00100"]
const ARROW_NONE := ["00000", "00000", "00000", "00000", "00000", "00000", "00000"]

var _img: Image
var _tex: ImageTexture
var _mat: StandardMaterial3D
var _last := ""


## width_m: ekranin dunya genisligi [m]. Yukseklik orana gore hesaplanir.
static func create(parent: Node3D, pos: Vector3, width_m: float,
		rot_deg := Vector3.ZERO) -> LedDisplay:
	var d := LedDisplay.new()

	var h := width_m * float(ROWS) / float(COLS)
	var qm := QuadMesh.new()
	qm.size = Vector2(width_m, h)
	d.mesh = qm

	d._img = Image.create(COLS * CELL, ROWS * CELL, true, Image.FORMAT_RGB8)
	d._img.fill(C_BG)
	d._img.generate_mipmaps()
	d._tex = ImageTexture.create_from_image(d._img)

	# LED ekran kendi isigini yayar: gölgesiz (unshaded) + doku dogrudan cikar.
	# Ayrica emission ile hafif parlama (glow) verilir.
	d._mat = StandardMaterial3D.new()
	d._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	d._mat.albedo_color = Color(1, 1, 1)
	d._mat.albedo_texture = d._tex
	d._mat.emission_enabled = true
	d._mat.emission_texture = d._tex
	d._mat.emission = Color(1, 1, 1)
	d._mat.emission_energy_multiplier = 0.9
	d._mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	d.material_override = d._mat

	d.position = pos
	d.rotation_degrees = rot_deg
	parent.add_child(d)
	d.set_text(" ", 0)
	return d


## text: 1 karakter (kat), arrow: 0 yok / 1 yukari / 2 asagi
func set_text(text: String, arrow: int) -> void:
	var key := text + "|" + str(arrow)
	if key == _last:
		return
	_last = key

	var ch := text.substr(0, 1).to_upper()
	if not FONT.has(ch):
		ch = "-"
	var glyph: Array = FONT[ch]
	var arr: Array = ARROW_NONE
	if arrow == LiftIo.DIR_UP:
		arr = ARROW_UP
	elif arrow == LiftIo.DIR_DOWN:
		arr = ARROW_DN

	_img.fill(C_BG)

	for row in range(ROWS):
		var a_line: String = arr[row]
		var g_line: String = glyph[row]
		for col in range(COLS):
			var on := false
			if col < 5:
				on = a_line[col] == "1"
			elif col >= 6:
				on = g_line[col - 6] == "1"
			_draw_dot(col, row, on)

	_img.generate_mipmaps()
	_tex.update(_img)


func _draw_dot(col: int, row: int, on: bool) -> void:
	var cx := col * CELL + CELL * 0.5
	var cy := row * CELL + CELL * 0.5
	var c := C_ON if on else C_DIM
	var r2 := DOT_R * DOT_R
	for y in range(CELL):
		for x in range(CELL):
			var px := col * CELL + x
			var py := row * CELL + y
			var dx := float(px) + 0.5 - cx
			var dy := float(py) + 0.5 - cy
			var d2 := dx * dx + dy * dy
			if d2 <= r2:
				_img.set_pixel(px, py, c)
			elif d2 <= r2 * 1.45:
				# yumusak kenar
				_img.set_pixel(px, py, c.lerp(C_BG, 0.55))


func set_energy(e: float) -> void:
	_mat.emission_energy_multiplier = e
