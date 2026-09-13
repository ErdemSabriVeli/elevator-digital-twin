class_name Braille

## Braille encoding and the physical dot geometry for tactile signage.
##
## Dot numbering inside a cell (the standard layout):
##     1  4
##     2  5
##     3  6
##
## Digits are not their own set of patterns: braille reuses the letters a-j and
## marks the run as numeric with a leading number sign. Floor "3" is therefore
## TWO cells, number sign + c, not one. Without the number sign the same dots
## read as the letter "c".
##
## The dimensions below are ADA 703.3 / Braille Authority of North America.
## They are an ergonomic spec, not styling: dots outside this range cannot be
## read reliably by a fingertip.

const DOT_BASE_M   := 0.0015   # dot base diameter            (ADA 1.5 - 1.6 mm)
const DOT_HEIGHT_M := 0.0008   # dot height                   (ADA 0.6 - 0.9 mm)
const DOT_PITCH_M  := 0.0024   # dot spacing within one cell  (ADA 2.3 - 2.5 mm)
const CELL_PITCH_M := 0.0062   # spacing between two cells    (ADA 6.1 - 7.6 mm)

## Dots 3-4-5-6. Introduces a run of digits.
const NUMBER_SIGN := [3, 4, 5, 6]

## Grade 1 letters. Dot lists are kept sorted so they compare directly.
const LETTER := {
	"a": [1],             "b": [1, 2],          "c": [1, 4],
	"d": [1, 4, 5],       "e": [1, 5],          "f": [1, 2, 4],
	"g": [1, 2, 4, 5],    "h": [1, 2, 5],       "i": [2, 4],
	"j": [2, 5],          "k": [1, 3],          "l": [1, 2, 3],
	"m": [1, 3, 4],       "n": [1, 3, 4, 5],    "o": [1, 3, 5],
	"p": [1, 2, 3, 4],    "q": [1, 2, 3, 4, 5], "r": [1, 2, 3, 5],
	"s": [2, 3, 4],       "t": [2, 3, 4, 5],    "u": [1, 3, 6],
	"v": [1, 2, 3, 6],    "w": [2, 4, 5, 6],    "x": [1, 3, 4, 6],
	"y": [1, 3, 4, 5, 6], "z": [1, 3, 5, 6],
}

## Which letter carries which digit:  a=1 ... i=9, j=0
const DIGIT_LETTER := "jabcdefghi"


## The cells for a label, as arrays of dot numbers. One number sign is emitted
## per run of digits, which is what makes "12" two digits rather than "ab".
static func cells(label: String) -> Array:
	var out: Array = []
	var in_number := false
	for i in label.length():
		var ch := label[i].to_lower()
		var u := ch.unicode_at(0)
		if u >= 48 and u <= 57:                       # 0-9
			if not in_number:
				out.append(NUMBER_SIGN.duplicate())
				in_number = true
			out.append((LETTER[DIGIT_LETTER[u - 48]] as Array).duplicate())
		else:
			in_number = false
			if ch == " ":
				out.append([])                        # blank cell
			elif LETTER.has(ch):
				out.append((LETTER[ch] as Array).duplicate())
	return out


## Offset of dot `n` (1..6) from dot 1 of its cell. +x right, +y up.
static func dot_offset(n: int) -> Vector2:
	var col := 0 if n <= 3 else 1
	var row := (n - 1) % 3
	return Vector2(col * DOT_PITCH_M, -row * DOT_PITCH_M)


## Overall width of a `count`-cell block, dot edge to dot edge.
static func width(count: int) -> float:
	if count <= 0:
		return 0.0
	return (count - 1) * CELL_PITCH_M + DOT_PITCH_M + DOT_BASE_M


## Overall height of one line, dot edge to dot edge.
static func height() -> float:
	return 2.0 * DOT_PITCH_M + DOT_BASE_M


## Raises the dots for `label` on `parent`. `origin` is the centre of dot 1 of
## the first cell; `face` is +1 or -1 for the surface normal along Z (the text
## runs left to right as seen from that side). Returns the cell count.
static func render(parent: Node3D, label: String, origin: Vector3,
		face: float, m: Material) -> int:
	var fz: float = signf(face)
	var cs := cells(label)
	for k in range(cs.size()):
		for n in cs[k]:
			var o := dot_offset(n)
			var p := origin + Vector3((k * CELL_PITCH_M + o.x) * fz, o.y, 0.0)
			var d := Vis.dome(parent, DOT_BASE_M * 0.5, DOT_HEIGHT_M, p, m)
			d.rotation_degrees = Vector3(90.0 * fz, 0, 0)
	return cs.size()
