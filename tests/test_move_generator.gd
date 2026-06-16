extends SceneTree
## Unit tests for CatanEngine.BoardPosition.generate_moves()
## Run from CLI: godot --headless -s tests/test_move_generator.gd

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
	print("=== CatanEngine Move Generator tests ===\n")

	# --- Setup phase move generation tests ---
	test_movegen_setup_forward_returns_settlement_moves()
	test_movegen_setup_backward_returns_settlement_moves()
	test_movegen_setup_settlement_after_settlement()
	test_movegen_setup_road_after_settlement()
	test_movegen_setup_only_returns_valid_vertices()

	# --- Main phase move generation tests ---
	test_movegen_main_always_includes_end_turn()
	test_movegen_main_no_build_moves_without_resources()
	test_movegen_main_build_settlement_requires_connected_road()

	# --- Robber phase tests ---
	test_movegen_robber_returns_move_robber_moves()
	test_movegen_robber_skips_desert_hexes()
	test_movegen_robber_skips_hex_with_current_robber()

	# --- Discard phase tests ---
	test_movegen_discard_returns_discard_move()

	# --- Road building phase tests ---
	test_movegen_road_building_returns_road_moves()
	test_movegen_road_building_skips_unowned_roads()
	
	test_movegen_trade_bank_moves_include_ratio()
	# test_movegen_buy_dev_card_available()
	# test_movegen_no_buy_dev_card_when_deck_empty()
	test_movegen_main_build_city_requires_ownership()
	test_movegen_main_build_road_requires_connected()
	test_movegen_main_build_road_with_settlement()
	test_integration_setup_roundtrip()
	test_integration_robber_roundtrip()
	test_movegen_main_multiple_players()

	# --- Summary ---
	print("\n=== Results ===")
	print("Passed: %d" % _passed)
	print("Failed: %d" % _failed)
	if _errors.size() > 0:
		print("\nFailures:")
		for e in _errors:
			print("  FAIL: %s" % e)
	print("===========================")


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# SETUP PHASE TESTS
# ---------------------------------------------------------------------------

func test_movegen_setup_forward_returns_settlement_moves() -> void:
	var pos := _board(3)
	# In SETUP_FORWARD phase, should generate settlement moves
	var moves := pos.generate_moves()
	_assert_eq(moves.size() > 0, true, "movegen setup_forward: generates moves")
	for m in moves:
		_assert_eq(m.type, CatanEngine.Move.Type.SETTLEMENT,
			"movegen setup_forward: all moves are SETTLEMENT")

func test_movegen_setup_backward_returns_settlement_moves() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.SETUP_BACKWARD
	var moves := pos.generate_moves()
	_assert_eq(moves.size() > 0, true, "movegen setup_backward: generates moves")
	for m in moves:
		_assert_eq(m.type, CatanEngine.Move.Type.SETTLEMENT,
			"movegen setup_backward: all moves are SETTLEMENT")

func test_movegen_setup_settlement_after_settlement() -> void:
	var pos := _board(3)
	# Place a settlement and check next phase generates road moves
	var vid := -1
	for v in pos.vertices:
		if not v.is_built():
			vid = v.id
			break
	var m := _move(CatanEngine.Move.Type.SETTLEMENT)
	m.vertex_id = vid
	pos = _engine.apply_move(pos, m)

	# Now we're in "waiting for road" state
	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "movegen after settlement: generates road moves")
	for mv in moves:
		_assert_eq(mv.type, CatanEngine.Move.Type.ROAD,
			"movegen after settlement: all moves are ROAD")

func test_movegen_setup_road_after_settlement() -> void:
	var pos := _board(3)
	var vid := -1
	for v in pos.vertices:
		if not v.is_built():
			vid = v.id
			break
	var ms := _move(CatanEngine.Move.Type.SETTLEMENT)
	ms.vertex_id = vid
	pos = _engine.apply_move(pos, ms)

	# Place a road adjacent to the settlement
	var rid := -1
	for r in pos.roads:
		if r.owner_id == -1 and (r.vertex_a_id == vid or r.vertex_b_id == vid):
			rid = r.id
			break
	var mr := _move(CatanEngine.Move.Type.ROAD)
	mr.road_id = rid
	pos = _engine.apply_move(pos, mr)

	# After road placement, should be ready for next player's settlement
	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "movegen after road: generates moves")
	_assert(moves[0].type == CatanEngine.Move.Type.SETTLEMENT,
		"movegen after road: generates SETTLEMENT for next player")

func test_movegen_setup_only_returns_valid_vertices() -> void:
	var pos := _board(3)
	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "movegen: has moves")

	# Every generated settlement vertex should be unoccupied
	for m in moves:
		var vid := m.vertex_id
		_assert_eq(pos.vertices[vid].is_built(), false,
			"movegen setup: vertex %d is not already built" % vid)


# ---------------------------------------------------------------------------
# MAIN PHASE TESTS
# ---------------------------------------------------------------------------

func test_movegen_main_always_includes_end_turn() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	var moves := pos.generate_moves()
	var has_end_turn := false
	for m in moves:
		if m.type == CatanEngine.Move.Type.END_TURN:
			has_end_turn = true
			break
	_assert(has_end_turn, "movegen main: END_TURN is always available")

func test_movegen_main_no_build_moves_without_resources() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Player has no resources
	var moves := pos.generate_moves()
	var build_moves := 0
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_SETTLEMENT:
			build_moves += 1
	_assert_eq(build_moves, 0, "movegen main: no build_settlement moves without resources")

func test_movegen_main_build_settlement_requires_connected_road() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give resources for settlement
	pos.players[0].resources["wood"] = 1
	pos.players[0].resources["brick"] = 1
	pos.players[0].resources["sheep"] = 1
	pos.players[0].resources["wheat"] = 1

	# Place a road to connect to
	var rid := -1
	var vid_for_road := -1
	for r in pos.roads:
		if r.owner_id == -1:
			rid = r.id
			vid_for_road = r.vertex_a_id
			break
	# Claim the road for player 0
	pos.roads[rid].owner_id = 0

	var moves := pos.generate_moves()
	var can_build := false
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_SETTLEMENT:
			can_build = true
			break
	_assert(can_build, "movegen main: can build settlement next to owned road")


# ---------------------------------------------------------------------------
# ROBBER PHASE TESTS
# ---------------------------------------------------------------------------

func test_movegen_robber_returns_move_robber_moves() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.ROBBER
	pos.current_player = 0
	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "movegen robber: generates moves")
	for m in moves:
		_assert_eq(m.type, CatanEngine.Move.Type.MOVE_ROBBER,
			"movegen robber: all moves are MOVE_ROBBER")

func test_movegen_robber_skips_desert_hexes() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.ROBBER
	pos.current_player = 0

	# Find desert hex
	var desert_hex_id := -1
	for h in pos.hexes:
		if h.resource == "desert":
			desert_hex_id = h.id
			break

	var moves := pos.generate_moves()
	for m in moves:
		_assert(m.robber_hex_id != desert_hex_id,
			"movegen robber: does not suggest desert hex")

func test_movegen_robber_skips_hex_with_current_robber() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.ROBBER
	pos.current_player = 0

	# Find hex with robber (desert typically starts with robber)
	var robber_hex_id := -1
	for h in pos.hexes:
		if h.has_robber:
			robber_hex_id = h.id
			break

	var moves := pos.generate_moves()
	for m in moves:
		_assert(m.robber_hex_id != robber_hex_id,
			"movegen robber: does not suggest hex already containing robber")


# ---------------------------------------------------------------------------
# DISCARD PHASE TESTS
# ---------------------------------------------------------------------------

func test_movegen_discard_returns_discard_move() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.DISCARD
	pos.current_player = 0
	pos.players_to_discard = [true, false, false]
	pos.players[0].resources["wood"] = 8
	pos.players[0].resources["brick"] = 8

	var moves := pos.generate_moves()
	_assert(moves.size() == 1, "movegen discard: returns exactly one move")
	_assert_eq(moves[0].type, CatanEngine.Move.Type.DISCARD,
		"movegen discard: move is DISCARD type")
	_assert(moves[0].discard_resources.has("wood") or moves[0].discard_resources.has("brick"),
		"movegen discard: includes resources to discard")


# ---------------------------------------------------------------------------
# ROAD BUILDING PHASE TESTS
# ---------------------------------------------------------------------------

func test_movegen_road_building_returns_road_moves() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.ROAD_BUILDING
	pos.current_player = 0
	pos.free_roads_remaining = 2

	# Place a settlement for player 0 to enable road placement
	var vid := -1
	for v in pos.vertices:
		if not v.is_built():
			vid = v.id
			v.owner_id = 0
			break

	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "movegen road_building: generates road moves")

	# Filter out END_TURN
	var road_moves := 0
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_ROAD:
			road_moves += 1
	_assert(road_moves > 0, "movegen road_building: has BUILD_ROAD moves")

func test_movegen_road_building_skips_unowned_roads() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.ROAD_BUILDING
	pos.current_player = 0
	pos.free_roads_remaining = 2

	# Place a settlement for player 0 to enable road placement
	var vid := -1
	for v in pos.vertices:
		if not v.is_built():
			vid = v.id
			v.owner_id = 0
			break

	# Pre-claim some roads for other players
	pos.roads[0].owner_id = 1
	pos.roads[1].owner_id = 2

	var moves := pos.generate_moves()
	for m in moves:
		_assert(m.road_id != 0 and m.road_id != 1,
			"movegen road_building: does not suggest already-built roads")


# ---------------------------------------------------------------------------
# MOVE GENERATION HELPER TESTS
# ---------------------------------------------------------------------------

func test_movegen_trade_bank_moves_include_ratio() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give 4 of each resource
	for r in CatanEngine.RESOURCE_TYPES:
		pos.players[0].resources[r] = 4

	var moves := pos.generate_moves()
	for m in moves:
		if m.type == CatanEngine.Move.Type.TRADE_BANK:
			_assert_eq(m.bank_give_amount, 4, "movegen trade: default ratio is 4")

func test_movegen_buy_dev_card_available() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	pos.dev_deck_remaining = 1
	# Give dev card cost
	pos.players[0].resources["sheep"] = 1
	pos.players[0].resources["wheat"] = 1
	pos.players[0].resources["ore"] = 1

	var moves := pos.generate_moves()
	var has_buy_dev := false
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUY_DEV_CARD:
			has_buy_dev = true
			break
	_assert(has_buy_dev, "movegen main: buy dev card available with resources and deck remaining")


# ---------------------------------------------------------------------------
# EDGE CASE TESTS
# ---------------------------------------------------------------------------

func test_movegen_no_buy_dev_card_when_deck_empty() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	pos.dev_deck_remaining = 0
	# Give dev card cost
	for r in CatanEngine.RESOURCE_TYPES:
		pos.players[0].resources[r] = 1

	var moves := pos.generate_moves()
	for m in moves:
		_assert_ne(m.type, CatanEngine.Move.Type.BUY_DEV_CARD,
			"movegen main: no buy dev card when deck empty")

func _assert_ne(a, b, msg: String) -> void:
	_assert(a != b, "%s (got %s, expected not equal to %s)" % [msg, str(a), str(b)])


# ---------------------------------------------------------------------------
# MAIN PHASE - BUILD MOVE TESTS
# ---------------------------------------------------------------------------

func test_movegen_main_build_city_requires_ownership() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give city cost
	pos.players[0].resources["wheat"] = 2
	pos.players[0].resources["ore"] = 3

	var moves := pos.generate_moves()
	var city_moves := 0
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_CITY:
			city_moves += 1
	_assert_eq(city_moves, 0, "movegen main: no city moves without owned settlements")


func test_movegen_main_build_road_requires_connected() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give road cost
	pos.players[0].resources["wood"] = 1
	pos.players[0].resources["brick"] = 1

	var moves := pos.generate_moves()
	var road_moves := 0
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_ROAD:
			road_moves += 1
	_assert_eq(road_moves, 0, "movegen main: no road moves without connection")


func test_movegen_main_build_road_with_settlement() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give road cost
	pos.players[0].resources["wood"] = 1
	pos.players[0].resources["brick"] = 1

	# Place a settlement for player 0
	for v in pos.vertices:
		if not v.is_built():
			v.owner_id = 0
			break

	var moves := pos.generate_moves()
	var road_moves := 0
	for m in moves:
		if m.type == CatanEngine.Move.Type.BUILD_ROAD:
			road_moves += 1
	_assert(road_moves > 0, "movegen main: can build road adjacent to owned settlement")


# ---------------------------------------------------------------------------
# PORT TRADE TESTS
# ---------------------------------------------------------------------------

func test_movegen_31_port_trade_ratio() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	# Give 3 of each resource
	for r in CatanEngine.RESOURCE_TYPES:
		pos.players[0].resources[r] = 3

	# Place settlement on 3:1 port
	for v in pos.vertices:
		if not v.is_built() and v.port != "":
			v.owner_id = 0
			break

	var moves := pos.generate_moves()
	var found_3_to_1 := false
	for m in moves:
		if m.type == CatanEngine.Move.Type.TRADE_BANK and m.bank_give_amount == 3:
			found_3_to_1 = true
			break
	_assert(found_3_to_1, "movegen main: 3:1 port trade available")


# ---------------------------------------------------------------------------
# INTEGRATION TESTS - movegen then apply_move
# ---------------------------------------------------------------------------

func test_integration_setup_roundtrip() -> void:
	var pos := _board(3)
	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "integration: setup generates moves")

	for m in moves:
		var result := _engine.apply_move(pos, m)
		_assert_eq(result.vertices[m.vertex_id].owner_id, 0, "integration: settlement applied")
		# After settlement, next move should be road
		var next_moves := result.generate_moves()
		for nm in next_moves:
			if nm.type == CatanEngine.Move.Type.ROAD:
				var after_road := _engine.apply_move(result, nm)
				_assert(after_road.roads[nm.road_id].owner_id == 0, "integration: road applied")
				break
		break  # Only test first setup move


func test_integration_robber_roundtrip() -> void:
	var pos := _board(3)
	pos.phase = CatanEngine.Phase.ROAD_BUILDING
	pos.free_roads_remaining = 0
	pos.phase = CatanEngine.Phase.ROBBER
	pos.current_player = 0
	pos.robber_player = 0

	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "integration: robber generates moves")

	for m in moves:
		var result := _engine.apply_move(pos, m)
		_assert_eq(result.hexes[m.robber_hex_id].has_robber, true, "integration: robber moved")
		break


# ---------------------------------------------------------------------------
# ALL PLAYERS MOVE GEN TESTS
# ---------------------------------------------------------------------------

func test_movegen_main_multiple_players() -> void:
	var pos := _board(4)
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 2
	# Give player 2 resources
	pos.players[2].resources["wood"] = 1
	pos.players[2].resources["brick"] = 1
	pos.players[2].resources["sheep"] = 1
	pos.players[2].resources["wheat"] = 1

	var moves := pos.generate_moves()
	_assert(moves.size() > 0, "movegen main: works with 4 players")


#func test_movegen_phase_transitions() -> void:
	#var pos := _board(3)
#
	## Test all phase types generate moves
	#pos.phase = CatanEngine.BoardPosition.Phase.ROLL
	#pos.current_player = 0
	#var moves := pos.generate_moves()
	## ROLL phase falls through to default (END_TURN only)
	#_assert_eq(moves.size(), 1, "movegen ROLL: only END_TURN")
#
	#pos.phase = CatanEngine.BoardPosition.Phase.DISCARD
	#pos.current_player = 0
	#pos.players[0].resources["wood"] = 8
	#pos.players_to_discard = [true, false, false]
	#moves = pos.generate_moves()
	#_assert(moves.size() > 0, "movegen DISCARD: generates moves")
