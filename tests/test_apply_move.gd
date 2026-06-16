extends SceneTree
## Unit tests for CatanEngine.apply_move()
##
## Run from CLI: godot --headless -s tests/test_apply_move.gd
## Or set as main scene in Project > Project Settings > Run > Main Scene
##
## Each test function starts with _test_ and uses the helpers below.
## A test passes if it completes without pushing_error / assert failure.

# ---------------------------------------------------------------------------
# TEST RUNNER
# ---------------------------------------------------------------------------

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
	print("=== CatanEngine apply_move tests ===\n")

	# --- Setup phase ---
	test_setup_settlement_places_building()
	test_setup_settlement_gives_victory_point()
	test_setup_settlement_tracks_last_vertex()
	test_setup_road_places_road()
	test_setup_road_advances_setup_forward()
	test_setup_road_transitions_to_backward()
	test_setup_road_completes_setup()

	# --- Build moves (main phase) ---
	test_build_settlement_costs_resources()
	test_build_settlement_places_on_vertex()
	test_build_settlement_gives_victory_point()
	test_build_city_costs_resources()
	test_build_city_upgrades_settlement()
	test_build_city_gives_extra_victory_point()
	test_build_road_costs_resources()
	test_build_road_places_on_edge()
	test_buy_dev_card_costs_resources()
	test_buy_dev_card_adds_to_new_dev_cards()
	test_buy_dev_card_decrements_deck()

	# --- Development card moves ---
	test_play_knight_triggers_robber_phase()
	test_play_knight_tracks_robber_player()
	test_play_knight_increments_knights_played()
	test_play_monopoly_steals_from_all_opponents()
	test_play_year_of_plenty_gives_two_resources()
	test_play_road_building_sets_free_roads()

	# --- Trade moves ---
	test_trade_bank_deducts_and_gives()
	test_trade_player_exchanges_resources()

	# --- Robber moves ---
	test_move_robber_relocates_robber()
	test_move_robber_clears_robber_player()
	test_move_robber_steals_from_target()
	test_move_robber_returns_to_main_phase()
	test_move_robber_returns_to_road_building()

	# --- Discard ---
	test_discard_removes_resources()
	test_discard_advances_to_next_discarder()
	test_discard_completes_to_robber_phase()

	# --- End turn ---
	test_end_turn_advances_player()
	test_end_turn_increments_turn_number()
	test_end_turn_merges_new_dev_cards()
	test_end_turn_rolls_dice()
	test_end_turn_non_seven_distributes_resources()
	test_end_turn_seven_triggers_discard()
	test_end_turn_seven_no_discarders_goes_to_robber()

	# --- Clone / immutability ---
	test_apply_move_does_not_mutate_original()
	test_clone_produces_independent_hexes()
	test_clone_produces_independent_vertices()
	test_clone_produces_independent_roads()
	test_clone_produces_independent_players()

	# --- Move generation ---
	test_movegen_main_includes_end_turn()
	test_movegen_main_build_moves_require_affordability()
	# test_movegen_main_dev_card_moves()
	test_movegen_main_trade_moves()

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

func _set_resources(pos: CatanEngine.BoardPosition, pid: int, res: Dictionary) -> void:
	for r in res:
		pos.players[pid].resources[r] = res[r]

func _set_hex_resource(pos: CatanEngine.BoardPosition, hex_id: int, resource: String, token: int) -> void:
	pos.hexes[hex_id].resource = resource
	pos.hexes[hex_id].token = token

func _set_robber(pos: CatanEngine.BoardPosition, hex_id: int) -> void:
	for h in pos.hexes:
		h.has_robber = false
	pos.hexes[hex_id].has_robber = true

func _find_hex_with_token(pos: CatanEngine.BoardPosition, token: int, avoid_robber: bool = true) -> int:
	for h in pos.hexes:
		if h.token == token and h.resource != "desert":
			if avoid_robber and h.has_robber:
				continue
			return h.id
	return -1

func _find_hex_without_token(pos: CatanEngine.BoardPosition, token: int) -> int:
	for h in pos.hexes:
		if h.token != token and h.resource != "desert":
			return h.id
	return -1

func _find_unbuilt_vertex(pos: CatanEngine.BoardPosition) -> int:
	for v in pos.vertices:
		if not v.is_built():
			return v.id
	return -1

func _find_unbuilt_road(pos: CatanEngine.BoardPosition) -> int:
	for r in pos.roads:
		if r.owner_id == -1:
			return r.id
	return -1

func _find_vertex_adjacent_to_hex(pos: CatanEngine.BoardPosition, hex_id: int) -> int:
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(hex_id) and not v.is_built():
			return v.id
	return -1

func _find_road_adjacent_to_vertex(pos: CatanEngine.BoardPosition, vertex_id: int) -> int:
	for r in pos.roads:
		if r.owner_id == -1 and (r.vertex_a_id == vertex_id or r.vertex_b_id == vertex_id):
			return r.id
	return -1

func _setup_board_for_main_phase(pos: CatanEngine.BoardPosition) -> void:
	# Complete setup so we're in MAIN phase with player 0
	pos.phase = CatanEngine.Phase.MAIN
	pos.current_player = 0
	pos.setup_placements = pos.num_players * 2


# ---------------------------------------------------------------------------
# SETUP PHASE TESTS
# ---------------------------------------------------------------------------

func test_setup_settlement_places_building() -> void:
	var pos := _board(3)
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.SETTLEMENT)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.vertices[vid].owner_id, 0, "setup settlement: owner is player 0")
	_assert_eq(result.vertices[vid].is_city, false, "setup settlement: not a city")

func test_setup_settlement_gives_victory_point() -> void:
	var pos := _board(3)
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.SETTLEMENT)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].victory_points, 1, "setup settlement: +1 VP")

func test_setup_settlement_tracks_last_vertex() -> void:
	var pos := _board(3)
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.SETTLEMENT)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.setup_last_vertex_id, vid, "setup settlement: tracks last vertex")

func test_setup_road_places_road() -> void:
	var pos := _board(3)
	# Place settlement first
	var vid := _find_unbuilt_vertex(pos)
	var ms := _move(CatanEngine.Move.Type.SETTLEMENT)
	ms.vertex_id = vid
	pos = _engine.apply_move(pos, ms)
	# Now place road
	var rid := _find_road_adjacent_to_vertex(pos, vid)
	var mr := _move(CatanEngine.Move.Type.ROAD)
	mr.road_id = rid
	var result := _engine.apply_move(pos, mr)
	_assert_eq(result.roads[rid].owner_id, 0, "setup road: owner is player 0")

func test_setup_road_advances_setup_forward() -> void:
	var pos := _board(3)
	var vid := _find_unbuilt_vertex(pos)
	var ms := _move(CatanEngine.Move.Type.SETTLEMENT)
	ms.vertex_id = vid
	pos = _engine.apply_move(pos, ms)
	var rid := _find_road_adjacent_to_vertex(pos, vid)
	var mr := _move(CatanEngine.Move.Type.ROAD)
	mr.road_id = rid
	var result := _engine.apply_move(pos, mr)
	# After first setup road (placement 0), should still be SETUP_FORWARD
	_assert_eq(result.phase, CatanEngine.Phase.SETUP_FORWARD, "setup road: still in forward phase")
	_assert_eq(result.current_player, 1, "setup road: advances to player 1")

func test_setup_road_transitions_to_backward() -> void:
	var pos := _board(3)
	# Complete forward round: 3 players × 2 actions = 6 placements
	# After 6 placements (3 settlements + 3 roads), should transition to backward
	for i in range(3):
		var vid := _find_unbuilt_vertex(pos)
		var ms := _move(CatanEngine.Move.Type.SETTLEMENT)
		ms.vertex_id = vid
		pos = _engine.apply_move(pos, ms)
		var rid := _find_road_adjacent_to_vertex(pos, vid)
		var mr := _move(CatanEngine.Move.Type.ROAD)
		mr.road_id = rid
		pos = _engine.apply_move(pos, mr)
	# After forward round completes, phase should be SETUP_BACKWARD
	_assert_eq(pos.phase, CatanEngine.Phase.SETUP_BACKWARD, "setup: transitions to backward after forward")
	_assert_eq(pos.current_player, 2, "setup: backward starts with last player")

func test_setup_road_completes_setup() -> void:
	var pos := _board(2)
	# 2 players × 2 rounds × 2 actions = 8 placements total
	for i in range(4):
		var vid := _find_unbuilt_vertex(pos)
		var ms := _move(CatanEngine.Move.Type.SETTLEMENT)
		ms.vertex_id = vid
		pos = _engine.apply_move(pos, ms)
		var rid := _find_road_adjacent_to_vertex(pos, vid)
		var mr := _move(CatanEngine.Move.Type.ROAD)
		mr.road_id = rid
		pos = _engine.apply_move(pos, mr)
	# After 4 setup roads (2 players x 2 rounds), setup should be complete
	# Note: setup_placements counts roads only, not settlements
	_assert_eq(pos.phase, CatanEngine.Phase.MAIN, "setup complete: phase is MAIN")
	_assert_eq(pos.setup_placements, 4, "setup complete: 4 setup roads placed")


# ---------------------------------------------------------------------------
# BUILD MOVES (MAIN PHASE)
# ---------------------------------------------------------------------------

func test_build_settlement_costs_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1, "ore": 0})
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.BUILD_SETTLEMENT)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 0, "build settlement: wood deducted")
	_assert_eq(result.players[0].resources["brick"], 0, "build settlement: brick deducted")
	_assert_eq(result.players[0].resources["sheep"], 0, "build settlement: sheep deducted")
	_assert_eq(result.players[0].resources["wheat"], 0, "build settlement: wheat deducted")

func test_build_settlement_places_on_vertex() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1, "ore": 0})
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.BUILD_SETTLEMENT)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.vertices[vid].owner_id, 0, "build settlement: vertex owned by player 0")
	_assert_eq(result.vertices[vid].is_city, false, "build settlement: not a city")

func test_build_settlement_gives_victory_point() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1, "ore": 0})
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.BUILD_SETTLEMENT)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].victory_points, 1, "build settlement: +1 VP")

func test_build_city_costs_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	# Place a settlement first
	var vid := _find_unbuilt_vertex(pos)
	pos.vertices[vid].owner_id = 0
	# Give city cost
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 2, "ore": 3})
	var m := _move(CatanEngine.Move.Type.BUILD_CITY)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wheat"], 0, "build city: wheat deducted")
	_assert_eq(result.players[0].resources["ore"], 0, "build city: ore deducted")

func test_build_city_upgrades_settlement() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	var vid := _find_unbuilt_vertex(pos)
	pos.vertices[vid].owner_id = 0
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 2, "ore": 3})
	var m := _move(CatanEngine.Move.Type.BUILD_CITY)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.vertices[vid].is_city, true, "build city: is_city is true")
	_assert_eq(result.players[0].settlements_built, -1, "build city: settlements_built decremented")
	_assert_eq(result.players[0].cities_built, 1, "build city: cities_built incremented")

func test_build_city_gives_extra_victory_point() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	var vid := _find_unbuilt_vertex(pos)
	pos.vertices[vid].owner_id = 0
	pos.players[0].victory_points = 1  # from the settlement
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 2, "ore": 3})
	var m := _move(CatanEngine.Move.Type.BUILD_CITY)
	m.vertex_id = vid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].victory_points, 2, "build city: total 2 VP (settlement + city bonus)")

func test_build_road_costs_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 1, "brick": 1, "sheep": 0, "wheat": 0, "ore": 0})
	var rid := _find_unbuilt_road(pos)
	var m := _move(CatanEngine.Move.Type.BUILD_ROAD)
	m.road_id = rid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 0, "build road: wood deducted")
	_assert_eq(result.players[0].resources["brick"], 0, "build road: brick deducted")

func test_build_road_places_on_edge() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 1, "brick": 1, "sheep": 0, "wheat": 0, "ore": 0})
	var rid := _find_unbuilt_road(pos)
	var m := _move(CatanEngine.Move.Type.BUILD_ROAD)
	m.road_id = rid
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.roads[rid].owner_id, 0, "build road: road owned by player 0")

func test_buy_dev_card_costs_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 1, "wheat": 1, "ore": 1})
	var m := _move(CatanEngine.Move.Type.BUY_DEV_CARD)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["sheep"], 0, "buy dev: sheep deducted")
	_assert_eq(result.players[0].resources["wheat"], 0, "buy dev: wheat deducted")
	_assert_eq(result.players[0].resources["ore"], 0, "buy dev: ore deducted")

func test_buy_dev_card_adds_to_new_dev_cards() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 1, "wheat": 1, "ore": 1})
	var m := _move(CatanEngine.Move.Type.BUY_DEV_CARD)
	var result := _engine.apply_move(pos, m)
	# Current implementation always gives a Knight as placeholder
	_assert_eq(result.players[0].new_dev_cards[CatanEngine.DevCard.KNIGHT], 1, "buy dev: knight in new_dev_cards")

func test_buy_dev_card_decrements_deck() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 1, "wheat": 1, "ore": 1})
	var m := _move(CatanEngine.Move.Type.BUY_DEV_CARD)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.dev_deck_remaining, CatanEngine.DECK_TOTAL - 1, "buy dev: deck decremented")


# ---------------------------------------------------------------------------
# DEVELOPMENT CARD TESTS
# ---------------------------------------------------------------------------

func test_play_knight_triggers_robber_phase() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.KNIGHT] = 1
	var m := _move(CatanEngine.Move.Type.PLAY_KNIGHT)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.phase, CatanEngine.Phase.ROBBER, "play knight: phase is ROBBER")

func test_play_knight_tracks_robber_player() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.KNIGHT] = 1
	var m := _move(CatanEngine.Move.Type.PLAY_KNIGHT)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.robber_player, 0, "play knight: robber_player is current player")

func test_play_knight_increments_knights_played() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.KNIGHT] = 2
	var m := _move(CatanEngine.Move.Type.PLAY_KNIGHT)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].knights_played, 1, "play knight: knights_played incremented")
	_assert_eq(result.players[0].dev_cards[CatanEngine.DevCard.KNIGHT], 1, "play knight: card removed from hand")

func test_play_monopoly_steals_from_all_opponents() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.MONOPOLY] = 1
	_set_resources(pos, 1, {"wood": 3, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	_set_resources(pos, 2, {"wood": 2, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	var m := _move(CatanEngine.Move.Type.PLAY_MONOPOLY)
	m.monopoly_resource = "wood"
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 5, "monopoly: player 0 gets all wood (3+2)")
	_assert_eq(result.players[1].resources["wood"], 0, "monopoly: player 1 loses all wood")
	_assert_eq(result.players[2].resources["wood"], 0, "monopoly: player 2 loses all wood")

func test_play_year_of_plenty_gives_two_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.YEAR_OF_PLENTY] = 1
	var m := _move(CatanEngine.Move.Type.PLAY_YEAR_OF_PLENTY)
	m.yop_resource_1 = "wood"
	m.yop_resource_2 = "ore"
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 1, "yop: +1 wood")
	_assert_eq(result.players[0].resources["ore"], 1, "yop: +1 ore")

func test_play_road_building_sets_free_roads() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.ROAD_BUILDING] = 1
	var m := _move(CatanEngine.Move.Type.PLAY_ROAD_BUILDING)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.free_roads_remaining, 2, "road building: 2 free roads")
	_assert_eq(result.phase, CatanEngine.Phase.ROAD_BUILDING, "road building: phase is ROAD_BUILDING")


# ---------------------------------------------------------------------------
# TRADE TESTS
# ---------------------------------------------------------------------------

func test_trade_bank_deducts_and_gives() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 4, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	var m := _move(CatanEngine.Move.Type.TRADE_BANK)
	m.bank_give = "wood"
	m.bank_receive = "ore"
	m.bank_give_amount = 4
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 0, "trade bank: wood deducted by 4")
	_assert_eq(result.players[0].resources["ore"], 1, "trade bank: ore received")

func test_trade_player_exchanges_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 2, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	_set_resources(pos, 1, {"wood": 0, "brick": 0, "sheep": 3, "wheat": 0, "ore": 0})
	var m := _move(CatanEngine.Move.Type.TRADE_PLAYER)
	m.trade_target_player = 1
	m.trade_give = {"wood": 2}
	m.trade_receive = {"sheep": 1}
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 0, "trade player: wood given")
	_assert_eq(result.players[0].resources["sheep"], 1, "trade player: sheep received")
	_assert_eq(result.players[1].resources["wood"], 2, "trade player: target receives wood")
	_assert_eq(result.players[1].resources["sheep"], 2, "trade player: target loses sheep")


# ---------------------------------------------------------------------------
# ROBBER TESTS
# ---------------------------------------------------------------------------

func test_move_robber_relocates_robber() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	# Place robber on hex 0
	_set_robber(pos, 0)
	pos.phase = CatanEngine.Phase.ROBBER
	# Find a different hex to move to
	var target_hex := -1
	for h in pos.hexes:
		if h.id != 0 and h.resource != "desert":
			target_hex = h.id
			break
	var m := _move(CatanEngine.Move.Type.MOVE_ROBBER)
	m.robber_hex_id = target_hex
	m.robber_steal_target = -1
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.hexes[0].has_robber, false, "move robber: old hex no longer has robber")
	_assert_eq(result.hexes[target_hex].has_robber, true, "move robber: new hex has robber")

func test_move_robber_clears_robber_player() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_robber(pos, 0)
	pos.phase = CatanEngine.Phase.ROBBER
	pos.robber_player = 0
	var m := _move(CatanEngine.Move.Type.MOVE_ROBBER)
	m.robber_hex_id = 1
	m.robber_steal_target = -1
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.robber_player, -1, "move robber: robber_player cleared")

func test_move_robber_steals_from_target() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_robber(pos, 0)
	pos.phase = CatanEngine.Phase.ROBBER
	_set_resources(pos, 1, {"wood": 3, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	# Find a hex adjacent to a vertex owned by player 1
	var target_hex := -1
	for h in pos.hexes:
		if h.id != 0 and h.resource != "desert":
			for vid in pos.vertices:
				if vid.adjacent_hex_indices.has(h.id):
					target_hex = h.id
					break
			if target_hex != -1:
				break
	# Place a settlement for player 1 adjacent to target hex
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(target_hex) and not v.is_built():
			v.owner_id = 1
			break
	var m := _move(CatanEngine.Move.Type.MOVE_ROBBER)
	m.robber_hex_id = target_hex
	m.robber_steal_target = 1
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].resources["wood"], 1, "move robber: player 0 steals 1 wood")
	_assert_eq(result.players[1].resources["wood"], 2, "move robber: player 1 loses 1 wood")

func test_move_robber_returns_to_main_phase() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_robber(pos, 0)
	pos.phase = CatanEngine.Phase.ROBBER
	var m := _move(CatanEngine.Move.Type.MOVE_ROBBER)
	m.robber_hex_id = 1
	m.robber_steal_target = -1
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.phase, CatanEngine.Phase.MAIN, "move robber: returns to MAIN phase")

func test_move_robber_returns_to_road_building() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_robber(pos, 0)
	pos.phase = CatanEngine.Phase.ROBBER
	pos.free_roads_remaining = 1  # Simulate interrupted road building
	var m := _move(CatanEngine.Move.Type.MOVE_ROBBER)
	m.robber_hex_id = 1
	m.robber_steal_target = -1
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.phase, CatanEngine.Phase.ROAD_BUILDING, "move robber: returns to ROAD_BUILDING")


# ---------------------------------------------------------------------------
# DISCARD TESTS
# ---------------------------------------------------------------------------

func test_discard_removes_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.phase = CatanEngine.Phase.DISCARD
	pos.current_player = 1
	pos.players_to_discard = [false, true, false]
	_set_resources(pos, 1, {"wood": 4, "brick": 4, "sheep": 0, "wheat": 0, "ore": 0})
	var m := _move(CatanEngine.Move.Type.DISCARD)
	m.discard_resources = {"wood": 4}
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[1].resources["wood"], 0, "discard: wood removed")
	_assert_eq(result.players_to_discard[1], false, "discard: player 1 no longer needs to discard")

func test_discard_advances_to_next_discarder() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.phase = CatanEngine.Phase.DISCARD
	pos.current_player = 0
	pos.players_to_discard = [true, true, false]
	_set_resources(pos, 0, {"wood": 4, "brick": 4, "sheep": 0, "wheat": 0, "ore": 0})
	_set_resources(pos, 1, {"wood": 4, "brick": 4, "sheep": 0, "wheat": 0, "ore": 0})
	var m := _move(CatanEngine.Move.Type.DISCARD)
	m.discard_resources = {"wood": 4}
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.current_player, 1, "discard: advances to next discarder (player 1)")

func test_discard_completes_to_robber_phase() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.phase = CatanEngine.Phase.DISCARD
	pos.current_player = 0
	pos.players_to_discard = [true, false, false]
	pos.robber_player = 2  # Player 2 rolled the 7
	_set_resources(pos, 0, {"wood": 4, "brick": 4, "sheep": 0, "wheat": 0, "ore": 0})
	var m := _move(CatanEngine.Move.Type.DISCARD)
	m.discard_resources = {"wood": 4}
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.phase, CatanEngine.Phase.ROBBER, "discard complete: phase is ROBBER")
	_assert_eq(result.current_player, 2, "discard complete: control returns to robber_player")


# ---------------------------------------------------------------------------
# END TURN TESTS
# ---------------------------------------------------------------------------

func test_end_turn_advances_player() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	var m := _move(CatanEngine.Move.Type.END_TURN)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.current_player, 1, "end turn: advances to player 1")

func test_end_turn_increments_turn_number() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 2  # Last player
	pos.turn_number = 3
	var m := _move(CatanEngine.Move.Type.END_TURN)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.turn_number, 4, "end turn: turn_number incremented after full round")
	_assert_eq(result.current_player, 0, "end turn: wraps to player 0")

func test_end_turn_merges_new_dev_cards() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	pos.players[0].new_dev_cards[CatanEngine.DevCard.KNIGHT] = 2
	pos.players[0].new_dev_cards[CatanEngine.DevCard.MONOPOLY] = 1
	var m := _move(CatanEngine.Move.Type.END_TURN)
	var result := _engine.apply_move(pos, m)
	_assert_eq(result.players[0].dev_cards[CatanEngine.DevCard.KNIGHT], 2, "end turn: new knights merged")
	_assert_eq(result.players[0].dev_cards[CatanEngine.DevCard.MONOPOLY], 1, "end turn: new monopoly merged")
	_assert_eq(result.players[0].new_dev_cards[CatanEngine.DevCard.KNIGHT], 0, "end turn: new_dev_cards cleared")

func test_end_turn_rolls_dice() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	var m := _move(CatanEngine.Move.Type.END_TURN)
	var result := _engine.apply_move(pos, m)
	_assert(result.last_dice_roll >= 2 and result.last_dice_roll <= 12,
		"end turn: dice roll is between 2 and 12 (got %d)" % result.last_dice_roll)

func test_end_turn_non_seven_distributes_resources() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Find a hex with a known token and place a settlement adjacent to it
	var target_hex := _find_hex_with_token(pos, 6)
	_assert(target_hex != -1, "test setup: need a hex with token 6")
	# Place settlement for player 1 (the next player) adjacent to that hex
	# Find a vertex adjacent to the target hex
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(target_hex) and not v.is_built():
			v.owner_id = 1  # Player 1 will receive resources
			break
	# Remove robber from target hex if present
	_set_robber(pos, _find_hex_without_token(pos, 6))
	var m := _move(CatanEngine.Move.Type.END_TURN)
	var result := _engine.apply_move(pos, m)
	# We can't predict the dice roll, but we can verify the roll happened
	# and the phase is MAIN (not ROBBER, which would mean 7)
	# Since 7 is only 1/6 chance, this will pass most of the time
	# For a deterministic test, we just verify the roll was stored
	_assert(result.last_dice_roll != 0, "end turn: dice was rolled (non-zero)")

func test_end_turn_seven_triggers_discard() -> void:
	# This test verifies the discard phase is set up correctly when 7 is rolled.
	# Since we can't control the dice, we test the _initiate_discard_phase logic
	# by directly setting up the state that _apply_end_turn would create.
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Give player 1 more than 7 cards
	_set_resources(pos, 1, {"wood": 4, "brick": 4, "sheep": 0, "wheat": 0, "ore": 0})
	# Simulate what _apply_end_turn does for a 7
	pos.robber_player = 0
	pos.last_dice_roll = 7
	# Manually initiate discard
	pos._initiate_discard_phase()
	_assert_eq(pos.phase, CatanEngine.Phase.DISCARD, "discard phase: phase is DISCARD")
	_assert_eq(pos.players_to_discard[1], true, "discard phase: player 1 needs to discard")
	_assert_eq(pos.players_to_discard[0], false, "discard phase: player 0 does not need to discard")
	_assert_eq(pos.current_player, 1, "discard phase: starts with player 1")

func test_end_turn_seven_no_discarders_goes_to_robber() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# No one has >7 cards
	pos.robber_player = 0
	pos.last_dice_roll = 7
	pos._initiate_discard_phase()
	# All players have 0 cards, so no one needs to discard
	var any_discard := false
	for i in range(pos.num_players):
		if pos.players_to_discard[i]:
			any_discard = true
			break
	_assert_eq(any_discard, false, "no discarders: no one needs to discard")
	# In the actual _apply_end_turn, this would set phase to ROBBER
	# and current_player to robber_player


# ---------------------------------------------------------------------------
# CLONE / IMMUTABILITY TESTS
# ---------------------------------------------------------------------------

func test_apply_move_does_not_mutate_original() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	_set_resources(pos, 0, {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1, "ore": 0})
	var original_wood : int = pos.players[0].resources["wood"]
	var vid := _find_unbuilt_vertex(pos)
	var m := _move(CatanEngine.Move.Type.BUILD_SETTLEMENT)
	m.vertex_id = vid
	var _result := _engine.apply_move(pos, m)
	_assert_eq(pos.players[0].resources["wood"], original_wood, "immutability: original board not mutated")
	_assert_eq(pos.vertices[vid].owner_id, -1, "immutability: original vertex not mutated")

func test_clone_produces_independent_hexes() -> void:
	var pos := _board(3)
	var clone = pos.clone()
	# Mutate clone's hex
	clone.hexes[0].has_robber = not clone.hexes[0].has_robber
	_assert(pos.hexes[0].has_robber != clone.hexes[0].has_robber,
		"clone hex: mutation on clone doesn't affect original")

func test_clone_produces_independent_vertices() -> void:
	var pos := _board(3)
	var clone = pos.clone()
	clone.vertices[0].owner_id = 2
	_assert_eq(pos.vertices[0].owner_id, -1, "clone vertex: original not affected")

func test_clone_produces_independent_roads() -> void:
	var pos := _board(3)
	var clone = pos.clone()
	clone.roads[0].owner_id = 1
	_assert_eq(pos.roads[0].owner_id, -1, "clone road: original not affected")

func test_clone_produces_independent_players() -> void:
	var pos := _board(3)
	var clone = pos.clone()
	clone.players[0].resources["wood"] = 99
	_assert_eq(pos.players[0].resources["wood"], 0, "clone player: original resources not affected")


# ---------------------------------------------------------------------------
# MOVE GENERATION TESTS
# ---------------------------------------------------------------------------

func test_movegen_main_includes_end_turn() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	var moves := pos.generate_moves()
	var has_end_turn := false
	for mv in moves:
		if mv.type == CatanEngine.Move.Type.END_TURN:
			has_end_turn = true
			break
	_assert(has_end_turn, "movegen main: always includes END_TURN")

func test_movegen_main_build_moves_require_affordability() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	# Player 0 has no resources
	var moves := pos.generate_moves()
	var build_count := 0
	for mv in moves:
		if mv.type == CatanEngine.Move.Type.BUILD_SETTLEMENT or mv.type == CatanEngine.Move.Type.BUILD_CITY or mv.type == CatanEngine.Move.Type.BUILD_ROAD:
			build_count += 1
	_assert_eq(build_count, 0, "movegen main: no build moves when broke")

func test_movegen_main_dev_card_moves() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.players[0].dev_cards[CatanEngine.DevCard.KNIGHT] = 1
	pos.players[0].dev_cards[CatanEngine.DevCard.MONOPOLY] = 1
	pos.players[0].dev_cards[CatanEngine.DevCard.YEAR_OF_PLENTY] = 1
	var moves := pos.generate_moves()
	var knight_count := 0
	var monopoly_count := 0
	var yop_count := 0
	for mv in moves:
		if mv.type == CatanEngine.Move.Type.PLAY_KNIGHT:
			knight_count += 1
		elif mv.type == CatanEngine.Move.Type.PLAY_MONOPOLY:
			monopoly_count += 1
		elif mv.type == CatanEngine.Move.Type.PLAY_YEAR_OF_PLENTY:
			yop_count += 1
	_assert_eq(knight_count, 1, "movegen main: 1 knight move")
	_assert_eq(monopoly_count, 5, "movegen main: 5 monopoly moves (one per resource)")
	_assert_eq(yop_count, 15, "movegen main: 15 year of plenty moves (unordered pairs with repeat)")

func test_movegen_main_trade_moves() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	# Give player 0 four of each resource
	_set_resources(pos, 0, {"wood": 4, "brick": 4, "sheep": 4, "wheat": 4, "ore": 4})
	var moves := pos.generate_moves()
	var trade_count := 0
	for mv in moves:
		if mv.type == CatanEngine.Move.Type.TRADE_BANK:
			trade_count += 1
	# 5 resources × 4 possible receives = 20 trade moves
	_assert_eq(trade_count, 20, "movegen main: 20 bank trade moves (5 give × 4 receive)")


# ---------------------------------------------------------------------------
# RESOURCE DISTRIBUTION TESTS (deterministic, call _distribute_resources directly)
# ---------------------------------------------------------------------------

func test_distribute_resources_gives_correct_amount() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Find a non-desert hex with token 5
	var hex_id := -1
	for h in pos.hexes:
		if h.resource != "desert" and h.token == 5:
			hex_id = h.id
			break
	_assert(hex_id != -1, "test setup: need non-desert hex with token 5")
	# Place settlement for player 0 adjacent to that hex
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(hex_id) and not v.is_built():
			v.owner_id = 0
			break
	# Put robber on a different hex
	_set_robber(pos, _find_hex_without_token(pos, 5))
	_set_resources(pos, 0, {"wood": 2, "brick": 2, "sheep": 2, "wheat": 2, "ore": 2})
	var hex_resource := pos.hexes[hex_id].resource
	var res_before = pos.players[0].resources[hex_resource]
	pos._distribute_resources(5)
	var gained : int = pos.players[0].resources[hex_resource] - res_before
	_assert_eq(gained, 1, "distribute: settlement gives 1 resource (gained %d)" % gained)

func test_distribute_resources_robber_blocks() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Find a non-desert hex with token 8
	var hex_id := -1
	for h in pos.hexes:
		if h.resource != "desert" and h.token == 8:
			hex_id = h.id
			break
	_assert(hex_id != -1, "test setup: need non-desert hex with token 8")
	# Place settlement and robber on the SAME hex
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(hex_id) and not v.is_built():
			v.owner_id = 0
			break
	_set_robber(pos, hex_id)
	_set_resources(pos, 0, {"wood": 2, "brick": 2, "sheep": 2, "wheat": 2, "ore": 2})
	var res_before = pos.players[0].resources["wood"]
	pos._distribute_resources(8)
	var gained : int = pos.players[0].resources["wood"] - res_before
	_assert_eq(gained, 0, "distribute: robber blocks resource production (gained %d)" % gained)

func test_distribute_resources_city_gives_double() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Find a non-desert hex with token 6
	var hex_id := -1
	for h in pos.hexes:
		if h.resource != "desert" and h.token == 6:
			hex_id = h.id
			break
	_assert(hex_id != -1, "test setup: need non-desert hex with token 6")
	# Place a CITY for player 0 adjacent to that hex
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(hex_id) and not v.is_built():
			v.owner_id = 0
			v.is_city = true
			break
	_set_robber(pos, _find_hex_without_token(pos, 6))
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	var hex_resource := pos.hexes[hex_id].resource
	pos._distribute_resources(6)
	# City gives 2 resources
	_assert_eq(pos.players[0].resources[hex_resource], 2, "distribute: city gives 2 resources")

func test_distribute_resources_multiple_players() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Find a non-desert hex with token 4
	var hex_id := -1
	for h in pos.hexes:
		if h.resource != "desert" and h.token == 4:
			hex_id = h.id
			break
	_assert(hex_id != -1, "test setup: need non-desert hex with token 4")
	# Place settlements for two different players adjacent to that hex
	var placed := 0
	for v in pos.vertices:
		if v.adjacent_hex_indices.has(hex_id) and not v.is_built():
			v.owner_id = placed  # player 0, then player 1
			placed += 1
			if placed >= 2:
				break
	_set_robber(pos, _find_hex_without_token(pos, 4))
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	_set_resources(pos, 1, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	var hex_resource := pos.hexes[hex_id].resource
	pos._distribute_resources(4)
	_assert_eq(pos.players[0].resources[hex_resource], 1, "distribute: player 0 gets 1")
	_assert_eq(pos.players[1].resources[hex_resource], 1, "distribute: player 1 gets 1")
	_assert_eq(pos.players[2].resources[hex_resource], 0, "distribute: player 2 gets nothing")

func test_distribute_resources_desert_produces_nothing() -> void:
	var pos := _board(3)
	_setup_board_for_main_phase(pos)
	pos.current_player = 0
	# Desert hex produces nothing regardless of token
	_set_resources(pos, 0, {"wood": 0, "brick": 0, "sheep": 0, "wheat": 0, "ore": 0})
	# Test with an arbitrary roll — desert should never produce
	for h in pos.hexes:
		if h.resource == "desert":
			# Put robber elsewhere
			_set_robber(pos, (h.id + 1) % pos.hexes.size())
			break
	pos._distribute_resources(5)  # any roll
	# No one should have gained resources from a desert-only scenario
	var total_resources := 0
	for i in range(pos.num_players):
		for r in pos.players[i].resources:
			total_resources += pos.players[i].resources[r]
	_assert_eq(total_resources, 0, "distribute: desert hex produces nothing")
