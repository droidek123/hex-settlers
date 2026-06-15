extends SceneTree
## Unit test: ensure move generator never offers moves on already-built vertices.
##
## Run: godot --headless -s tests/test_movegen_occupied_vertex.gd

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
	print("=== Test: movegen never offers occupied vertices ===\n")
	
	test_setup_settlement_excludes_occupied()
	test_setup_settlement_excludes_adjacent_to_occupied()
	test_main_settlement_excludes_occupied()
	test_main_settlement_excludes_adjacent_to_occupied()
	
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

func _board(num_players: int = 3) -> CatanEngine.BoardPosition:
	return _engine.new_game(num_players)

func _move(move_type: CatanEngine.Move.Type) -> CatanEngine.Move:
	return CatanEngine.Move.new(move_type)

# --- Tests ---

func test_setup_settlement_excludes_occupied() -> void:
	var pos := _board(3)
	# Manually occupy a vertex
	var target_vid := -1
	for v in pos.vertices:
		if not v.is_built():
			target_vid = v.id
			v.owner_id = 0  # mark as occupied
			break
	
	var moves := pos.generate_moves()
	# All moves should be SETTLEMENT type (setup phase)
	for m in moves:
		_assert(m.type == CatanEngine.Move.Type.SETTLEMENT,
			"setup: move is SETTLEMENT type")
		# The occupied vertex must NOT appear
		_assert(m.vertex_id != target_vid,
			"setup: occupied vertex %d is excluded from moves" % target_vid)

func test_setup_settlement_excludes_adjacent_to_occupied() -> void:
	var pos := _board(3)
	# Occupy a vertex, then verify its neighbours are excluded (distance rule)
	var target_vid := -1
	for v in pos.vertices:
		if not v.is_built():
			target_vid = v.id
			v.owner_id = 0
			break
	
	# Find neighbours (vertices sharing a road with target)
	var neighbour_ids: Array[int] = []
	for r in pos.roads:
		if r.vertex_a_id == target_vid:
			neighbour_ids.append(r.vertex_b_id)
		elif r.vertex_b_id == target_vid:
			neighbour_ids.append(r.vertex_a_id)
	
	var moves := pos.generate_moves()
	for m in moves:
		_assert(!(neighbour_ids.has(m.vertex_id)),
			"setup: neighbour of occupied vertex %d is excluded (distance rule)" % target_vid)

func test_main_settlement_excludes_occupied() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give resources for a settlement
	pos.players[0].resources["wood"] = 1
	pos.players[0].resources["brick"] = 1
	pos.players[0].resources["sheep"] = 1
	pos.players[0].resources["wheat"] = 1
	
	# Place an owned road so there's a valid placement spot
	var road_placed := false
	for r in pos.roads:
		if r.owner_id == -1:
			r.owner_id = 0
			road_placed = true
			break
	_assert(road_placed, "main: placed a test road")
	
	# Now occupy a vertex
	var target_vid := -1
	for v in pos.vertices:
		if not v.is_built():
			target_vid = v.id
			v.owner_id = 1  # occupied by ANOTHER player
			break
	
	var moves := pos.generate_moves()
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_SETTLEMENT:
			_assert(m.vertex_id != target_vid,
				"main: occupied vertex %d excluded from BUILD_SETTLEMENT" % target_vid)

func test_main_settlement_excludes_adjacent_to_occupied() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	pos.players[0].resources["wood"] = 1
	pos.players[0].resources["brick"] = 1
	pos.players[0].resources["sheep"] = 1
	pos.players[0].resources["wheat"] = 1
	
	# Place an owned road
	for r in pos.roads:
		if r.owner_id == -1:
			r.owner_id = 0
			break
	
	# Occupy a vertex
	var target_vid := -1
	for v in pos.vertices:
		if not v.is_built():
			target_vid = v.id
			v.owner_id = 0
			break
	
	# Find neighbours
	var neighbour_ids: Array[int] = []
	for r in pos.roads:
		if r.vertex_a_id == target_vid:
			neighbour_ids.append(r.vertex_b_id)
		elif r.vertex_b_id == target_vid:
			neighbour_ids.append(r.vertex_a_id)
	
	var moves := pos.generate_moves()
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_SETTLEMENT:
			_assert(!(neighbour_ids.has(m.vertex_id)),
				"main: neighbour of occupied vertex %d excluded (distance rule)" % target_vid)
