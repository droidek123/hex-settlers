extends SceneTree
## Unit tests for CatanEngine.evaluate()
##
## Run: godot --headless -s tests/test_evaluate.gd

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
	print("=== CatanEngine evaluate() tests ===\n")
	
	test_basic_count()
	test_one_settlement_per_player()
	test_player_with_city_scores_higher()
	test_extra_vp_increases_score()
	test_resources_increase_score()
	test_longest_road_bonus()
	test_largest_army_bonus()
	test_knights_played_increase_score()
	test_dev_cards_increase_score()
	test_robber_reduces_production_score()
	test_production_score_higher_for_better_hexes()
	
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

func _eval(pos: CatanEngine.BoardPosition) -> Array[float]:
	return _engine.evaluate(pos)

# --- Tests ---

func test_basic_count() -> void:
	var pos := _board(3)
	var scores := _eval(pos)
	_assert_eq(scores.size(), 3, "evaluate returns score for each player (3 players)")

func test_one_settlement_per_player() -> void:
	var pos := _board(2)
	# Give each player one settlement
	pos.vertices[0].owner_id = 0
	pos.vertices[1].owner_id = 1
	pos.players[0].settlements_built = 1
	pos.players[1].settlements_built = 1
	pos.players[0].victory_points = 1
	pos.players[1].victory_points = 1
	
	var scores := _eval(pos)
	_assert(scores[0] > 0, "player 0 has positive score")
	_assert(scores[1] > 0, "player 1 has positive score")
	# Both have same setup, scores should be close (may differ slightly due to different hex adjacency)
	_assert(abs(scores[0] - scores[1]) < 100.0,
		"players with same buildings have similar scores (diff=%.1f)" % abs(scores[0] - scores[1]))

func test_player_with_city_scores_higher() -> void:
	var pos := _board(2)
	# Player 0 has a settlement on vertex 0
	pos.vertices[0].owner_id = 0
	pos.players[0].settlements_built = 1
	pos.players[0].victory_points = 1
	# Player 1 has a city on vertex 1
	pos.vertices[1].owner_id = 1
	pos.vertices[1].is_city = true
	pos.players[1].cities_built = 1
	pos.players[1].victory_points = 2
	
	var scores := _eval(pos)
	_assert(scores[1] > scores[0],
		"player with city scores higher than player with settlement (%.1f vs %.1f)" % [scores[1], scores[0]])

func test_extra_vp_increases_score() -> void:
	var pos := _board(2)
	pos.vertices[0].owner_id = 0
	pos.players[0].settlements_built = 1
	pos.players[0].victory_points = 1
	
	var score_before := _eval(pos)[0]
	
	# Add a VP (from a VP dev card)
	pos.players[0].victory_points = 2
	var score_after := _eval(pos)[0]
	
	_assert(score_after > score_before,
		"extra VP increases score (%.1f -> %.1f)" % [score_before, score_after])

func test_resources_increase_score() -> void:
	var pos := _board(2)
	var score_before := _eval(pos)[0]
	
	pos.players[0].resources["wood"] = 5
	var score_after := _eval(pos)[0]
	
	_assert(score_after > score_before,
		"resources increase score (%.1f -> %.1f)" % [score_before, score_after])

func test_longest_road_bonus() -> void:
	var pos := _board(2)
	pos.longest_road_player = 0
	pos.longest_road_length = 5
	
	var scores := _eval(pos)
	_assert(scores[0] > scores[1],
		"longest road owner scores higher (%.1f vs %.1f)" % [scores[0], scores[1]])

func test_largest_army_bonus() -> void:
	var pos := _board(2)
	pos.largest_army_player = 1
	pos.largest_army_size = 3
	
	var scores := _eval(pos)
	_assert(scores[1] > scores[0],
		"largest army owner scores higher (%.1f vs %.1f)" % [scores[1], scores[0]])

func test_knights_played_increase_score() -> void:
	var pos := _board(3)
	var score_before := _eval(pos)[0]
	
	pos.players[0].knights_played = 2
	var score_after := _eval(pos)[0]
	
	_assert(score_after > score_before,
		"knights played increase score (%.1f -> %.1f)" % [score_before, score_after])

func test_dev_cards_increase_score() -> void:
	var pos := _board(3)
	var score_before := _eval(pos)[0]
	
	pos.players[0].dev_cards[CatanEngine.DevCard.KNIGHT] = 2
	pos.players[0].dev_cards[CatanEngine.DevCard.VICTORY_POINT] = 1
	var score_after := _eval(pos)[0]
	
	_assert(score_after > score_before,
		"dev cards increase score (%.1f -> %.1f)" % [score_before, score_after])

func test_robber_reduces_production_score() -> void:
	var pos := _board(2)
	# Place a settlement on a vertex adjacent to some hex
	for v in pos.vertices:
		if not v.is_built() and v.adjacent_hex_indices.size() > 0:
			v.owner_id = 0
			pos.players[0].settlements_built = 1
			break
	
	var score_without_robber := _eval(pos)[0]
	
	# Put robber on one of the adjacent hexes
	for hex_id in pos.vertices[0].adjacent_hex_indices:
		pos.hexes[hex_id].has_robber = true
		break
	
	var score_with_robber := _eval(pos)[0]
	
	_assert(score_with_robber <= score_without_robber,
		"robber reduces or maintains score (%.1f -> %.1f)" % [score_without_robber, score_with_robber])

func test_production_score_higher_for_better_hexes() -> void:
	var pos := _board(2)
	
	# Place a settlement on the first vertex with adjacent hexes
	var target_vid := -1
	for v in pos.vertices:
		if not v.is_built() and v.adjacent_hex_indices.size() >= 2:
			target_vid = v.id
			v.owner_id = 0
			pos.players[0].settlements_built = 1
			break
	_assert(target_vid >= 0, "found a vertex with hex adjacency")
	
	var score_initial := _eval(pos)[0]
	
	# Upgrade to city — should increase production score
	pos.vertices[target_vid].is_city = true
	pos.players[0].settlements_built = 0
	pos.players[0].cities_built = 1
	
	var score_city := _eval(pos)[0]
	_assert(score_city > score_initial,
		"city scores higher than settlement (%.1f -> %.1f)" % [score_initial, score_city])
