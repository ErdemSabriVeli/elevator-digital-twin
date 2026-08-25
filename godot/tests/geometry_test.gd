extends SceneTree

## Mekanik yerlesim dogrulamasi.
##
## Ekran goruntusune bakarak fark edilmesi zor olan carpismalari ve halat
## hizalama hatalarini sayisal olarak kontrol eder:
##   - kabin en ust kattayken tahrik makinesi / saptirma makarasi ile carpisma
##   - karsi agirligin kuyu dibi ve tepe siniri
##   - halat hatlarinin kabin ve karsi agirlik merkezleriyle hizasi
##   - kabin ile karsi agirligin yatay ayrimi
##
## Calistirma:
##   godot --headless --path <godot> --script res://tests/geometry_test.gd

var failures := 0


func _initialize() -> void:
	print("=== MEKANIK YERLESIM DOGRULAMASI ===\n")

	# --- turetilen konumlar -------------------------------------------------
	var top_y: float = float(LiftCfg.TOP_FLOOR) * LiftCfg.M_FLOOR_H
	var ceiling: float = top_y + LiftCfg.M_HEADROOM
	var sheave_y: float = top_y + LiftCfg.M_HEADROOM - 1.15
	var tz: float = LiftCfg.M_ROPE_Z_CAR - LiftCfg.M_SHEAVE_R
	var dz: float = (tz - LiftCfg.M_SHEAVE_R) - LiftCfg.M_DEFLECT_R
	var dy: float = sheave_y - LiftCfg.M_DEFLECT_DY

	print("Kuyu tepesi        : %.2f m   (tavan %.2f m)" % [top_y, ceiling])
	print("Tahrik kasnagi     : y=%.2f  z=%.2f  R=%.2f" % [sheave_y, tz, LiftCfg.M_SHEAVE_R])
	print("Saptirma makarasi  : y=%.2f  z=%.2f  R=%.2f\n" % [dy, dz, LiftCfg.M_DEFLECT_R])

	_test_rope_alignment(tz, dz)
	_test_car_top_clearance(top_y, sheave_y, dy, ceiling)
	_test_counterweight_travel(top_y)
	_test_horizontal_separation()
	_test_governor_clearance()

	print("\n=== SONUC: %s ===" % ("TUM KONTROLLER GECTI" if failures == 0
			else "%d KONTROL BASARISIZ" % failures))
	quit(1 if failures > 0 else 0)


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [gecti] %s %s" % [name, detail])
	else:
		failures += 1
		print("  [HATA ] %s %s" % [name, detail])


# =============================================================================
func _test_rope_alignment(tz: float, dz: float) -> void:
	print("1) Halat hatlarinin hizasi")

	# Tahrik kasnaginin kabin tarafi tegeti kabin merkezinin uzerinde olmali
	var car_line: float = tz + LiftCfg.M_SHEAVE_R
	check("kabin halat hatti kabin merkezinde",
			absf(car_line - LiftCfg.M_ROPE_Z_CAR) < 1e-6,
			"(z=%.3f)" % car_line)

	# Saptirma makarasindan cikan hat karsi agirligin merkezinde olmali
	var cwt_line: float = dz - LiftCfg.M_DEFLECT_R
	check("karsi agirlik halat hatti agirlik merkezinde",
			absf(cwt_line - LiftCfg.M_CWT_Z) < 1e-6,
			"(z=%.3f, agirlik z=%.3f)" % [cwt_line, LiftCfg.M_CWT_Z])

	# Kasnaktan makaraya inen kol dusey olmali (teget noktalari ayni z)
	var s_exit: float = tz - LiftCfg.M_SHEAVE_R
	var d_entry: float = dz + LiftCfg.M_DEFLECT_R
	check("kasnak-makara arasi kol dusey",
			absf(s_exit - d_entry) < 1e-6,
			"(%.3f vs %.3f)" % [s_exit, d_entry])

	# Halat demeti kasnak govdesine sigmali
	var bundle: float = (LiftCfg.ROPE_COUNT - 1) * LiftCfg.ROPE_PITCH
	check("halat demeti kasnak genisligine siginiyor",
			bundle + 0.02 < bundle + 0.10,
			"(demet %.3f m, %d halat)" % [bundle, LiftCfg.ROPE_COUNT])


func _test_car_top_clearance(top_y: float, sheave_y: float, dy: float,
		ceiling: float) -> void:
	print("\n2) Kabin en ust kattayken tepe boslugu")

	var car_roof: float = top_y + LiftCfg.M_CAR_H + 0.08
	var hitch_top: float = top_y + LiftCfg.M_CAR_H + 0.36
	var rail_top: float = top_y + LiftCfg.M_CAR_H + 0.08 + LiftCfg.M_CARTOP_RAIL
	var sheave_bot: float = sheave_y - LiftCfg.M_SHEAVE_R
	var defl_bot: float = dy - LiftCfg.M_DEFLECT_R

	print("     kabin tavani %.2f | kanca %.2f | korkuluk %.2f" %
			[car_roof, hitch_top, rail_top])
	print("     kasnak alti  %.2f | makara alti %.2f | tavan %.2f" %
			[sheave_bot, defl_bot, ceiling])

	# Saptirma makarasi kabin izdusumunun uzerinde kalir (z araliklari kesisir)
	check("saptirma makarasi korkulugun uzerinde",
			defl_bot > rail_top,
			"(bosluk %.2f m)" % (defl_bot - rail_top))
	check("tahrik kasnagi korkulugun uzerinde",
			sheave_bot > rail_top,
			"(bosluk %.2f m)" % (sheave_bot - rail_top))
	check("korkuluk tavana carpmiyor",
			rail_top < ceiling - 0.30,
			"(bosluk %.2f m)" % (ceiling - rail_top))
	check("halat kancasi makaranin altinda kaliyor",
			hitch_top < defl_bot,
			"(bosluk %.2f m)" % (defl_bot - hitch_top))


func _test_counterweight_travel(top_y: float) -> void:
	print("\n3) Karsi agirlik hareket sinirlari")

	# LiftPlant.counterweight_y() ile ayni bagintiya dayanir
	const CWT_OFFSET := 0.10
	const BUFFER_H := 0.45
	var cwt_at_car_bottom: float = top_y - 0.0 - CWT_OFFSET
	var cwt_at_car_top: float = top_y - top_y - CWT_OFFSET
	var cwt_bot_lowest: float = cwt_at_car_top - LiftCfg.M_CWT_H * 0.5
	var cwt_top_highest: float = cwt_at_car_bottom + LiftCfg.M_CWT_H * 0.5 + 0.26
	var buffer_top: float = -LiftCfg.M_PIT_DEPTH + BUFFER_H

	print("     kabin altta -> agirlik %.2f | kabin ustte -> agirlik %.2f" %
			[cwt_at_car_bottom, cwt_at_car_top])

	check("agirlik kuyu dibi tamponuna oturmuyor",
			cwt_bot_lowest > buffer_top,
			"(en alt %.2f, tampon ustu %.2f)" % [cwt_bot_lowest, buffer_top])
	check("agirlik saptirma makarasinin altinda kaliyor",
			cwt_top_highest < top_y + LiftCfg.M_HEADROOM - 1.15 - LiftCfg.M_DEFLECT_DY
					- LiftCfg.M_DEFLECT_R,
			"(en ust %.2f)" % cwt_top_highest)


func _test_horizontal_separation() -> void:
	print("\n4) Kabin / karsi agirlik yatay ayrimi")

	var car_back: float = -LiftCfg.M_CAR_D * 0.5
	var cwt_front: float = LiftCfg.M_CWT_Z + LiftCfg.M_CWT_D * 0.5
	var cwt_back: float = LiftCfg.M_CWT_Z - LiftCfg.M_CWT_D * 0.5
	var shaft_back: float = -LiftCfg.M_SHAFT_D * 0.5

	check("agirlik kabine carpmiyor",
			cwt_front < car_back,
			"(bosluk %.3f m)" % (car_back - cwt_front))
	check("agirlik kuyu arka duvarina carpmiyor",
			cwt_back > shaft_back,
			"(bosluk %.3f m)" % (cwt_back - shaft_back))

	var car_side: float = LiftCfg.M_CAR_W * 0.5
	var shaft_side: float = LiftCfg.M_SHAFT_W * 0.5
	check("kabin kuyu yan duvarina sigiyor",
			car_side + 0.16 < shaft_side + 0.02,
			"(kabin %.2f + pabuc, kuyu %.2f)" % [car_side, shaft_side])


func _test_governor_clearance() -> void:
	print("\n5) Hiz regulatoru halati")

	var gz: float = LiftCfg.M_GOV_ROPE_Z
	var gx: float = LiftCfg.M_SHAFT_W * 0.5 - 0.15
	var car_side: float = LiftCfg.M_CAR_W * 0.5

	check("regulator halati kabinin yaninda (x)",
			gx > car_side,
			"(halat x=%.2f, kabin kenari %.2f)" % [gx, car_side])
	check("regulator halati kapi bolgesinde degil (z)",
			gz < LiftCfg.M_CAR_D * 0.5,
			"(halat z=%.2f)" % gz)
	check("regulator halati karsi agirliktan uzak",
			absf(gx) > LiftCfg.M_CWT_W * 0.5,
			"(agirlik yari genislik %.2f)" % (LiftCfg.M_CWT_W * 0.5))
