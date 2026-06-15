extends SceneTree
## Test from_game_state: simulate a game node and verify conversion.
##
## Run: godot --headless -s tests/test_from_game_state.gd

var _engine: CatanEngine = null
var _passed: int = 0
var _failed: int = 0
var _errors: Array[String] = []

func _init() -> void:
	_engine = CatanEngine.new()
	run_all()
	_engine.free()
	quit()

func run_all() -> void:
	print("=== Test: from_game_state vertex matching ===\n")
	
	test_vertex_mapping_count()
	test_mapping_converts_keys_correctly()
	
	print("\n=== Results ===")
	print("Passed: %d" % _passed)
	print("Failed: %d" % _failed)
	for e in _errors:
		print("  FAIL: %s" % e)
	print("===========================")

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_errors.append(msg)
		print("  FAIL: %s" % msg)

func _assert_eq(a, b, msg: String) -> void:
	_assert(a == b, "%s (expected %s, got %s)" % [msg, str(b), str(a)])

# --- Test: vertex_key_to_id produced by topology init ---

func test_vertex_mapping_count() -> void:
	var pos := _engine.new_game(3)
	_assert_eq(pos.vertex_key_to_id.size(), 54,
		"vertex_key_to_id has 54 entries")
	_assert_eq(pos.vertices.size(), 54,
		"vertices array has 54 entries")
	_assert_eq(pos.road_key_to_id.size(), 72,
		"road_key_to_id has 72 entries")
	
	# Check that all keys are non-empty
	for ek in pos.vertex_key_to_id:
		_assert(ek.length() > 0, "engine key '%s' is non-empty" % ek)

func test_mapping_converts_keys_correctly() -> void:
	var pos := _engine.new_game(3)
	
	# Simulate what from_game_state does: convert engine keys to game keys
	# by adding board_offset (650, 450)
	var bo_x := 650
	var bo_y := 450
	
	var vid_to_game_key: Dictionary = {}
	for ek in pos.vertex_key_to_id:
		var vid: int = pos.vertex_key_to_id[ek]
		var parts = ek.split("_")
		var gk := "%d_%d" % [int(parts[0]) + bo_x, int(parts[1]) + bo_y]
		vid_to_game_key[vid] = gk
	
	_assert_eq(vid_to_game_key.size(), 54,
		"vid_to_game_key has 54 entries (all vertices mapped)")
	
	# Verify no duplicate game keys (would mean two engine vertices map to same game key)
	var seen_keys: Dictionary = {}
	var duplicates := 0
	for vid in vid_to_game_key:
		var gk = vid_to_game_key[vid]
		if seen_keys.has(gk):
			duplicates += 1
			print("  DUPLICATE: vid=%d and vid=%d both map to game_key=%s" % [vid, seen_keys[gk], gk])
		seen_keys[gk] = vid
	_assert_eq(duplicates, 0,
		"No duplicate game keys in mapping (%d found)" % duplicates)
	
	# Verify each game key has the expected format
	for vid in vid_to_game_key:
		var gk = vid_to_game_key[vid]
		var parts = gk.split("_")
		_assert(parts.size() == 2,
			"Game key '%s' for vid %d splits into 2 parts" % [gk, vid])
		var x := int(parts[0])
		var y := int(parts[1])
		# Game keys should have x >= 650 (board_offset.x) since engine coords start at 0 or higher? 
		# Actually some engine x coords might be negative (e.g. -42)
		_assert(x >= -42 + bo_x and x <= 105 + bo_x,
			"Game key x=%d for vid %d is in expected range" % [x, vid])
