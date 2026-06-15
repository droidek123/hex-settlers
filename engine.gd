extends Node
class_name CatanEngine

# ---------------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------------

const RESOURCE_TYPES: Array[String] = ["wood", "brick", "sheep", "wheat", "ore"]
const RESOURCE_COUNT: int = 5

# Fixed board topology: radius-2 hex grid = 19 hexes, 54 vertices, 72 roads.
const HEX_COUNT: int = 19
const VERTEX_COUNT: int = 54
const ROAD_COUNT: int = 72

# Hex size for pixel-space calculations (must match game.gd)
const HEX_SIZE: float = 42.0

const MAX_PLAYERS: int = 4
const INITIAL_SETTLEMENTS: int = 2
const INITIAL_ROADS: int = 2
const SETTLEMENT_VICTORY_POINTS: int = 1
const CITY_VICTORY_POINTS: int = 2
const POINTS_TO_WIN: int = 10

# Building costs
const ROAD_COST: Dictionary =       {"wood": 1, "brick": 1, "sheep": 0, "wheat": 0, "ore": 0}
const SETTLEMENT_COST: Dictionary = {"wood": 1, "brick": 1, "sheep": 1, "wheat": 1, "ore": 0}
const CITY_COST: Dictionary =       {"wood": 0, "brick": 0, "sheep": 0, "wheat": 2, "ore": 3}
const DEV_CARD_COST: Dictionary =   {"wood": 0, "brick": 0, "sheep": 1, "wheat": 1, "ore": 1}

# Development card deck composition (standard 25-card deck)
const DECK_KNIGHTS: int = 14
const DECK_VICTORY: int = 5
const DECK_MONOPOLY: int = 2
const DECK_YEAR_OF_PLENTY: int = 2
const DECK_ROAD_BUILDING: int = 2
const DECK_TOTAL: int = 25

# Resource counts on a standard 19-hex board
const HEX_RESOURCE_COUNTS: Dictionary = {
	"wood": 4, "brick": 3, "sheep": 4, "wheat": 4, "ore": 3, "desert": 1
}

# Token (number) counts on a standard board
const TOKEN_COUNTS: Dictionary = {
	2: 1, 3: 2, 4: 2, 5: 2, 6: 2, 8: 2, 9: 2, 10: 2, 11: 2, 12: 1
}


# ---------------------------------------------------------------------------
# ENUMS
# ---------------------------------------------------------------------------

enum Phase {
	SETUP_FORWARD,      # Initial placement round 1 (p0, p1, p2, p3)
	SETUP_BACKWARD,     # Initial placement round 2 (p3, p2, p1, p0)
	ROLL,               # Player must roll the dice
	MAIN,               # After roll, before end turn — build, trade, play cards
	DISCARD,            # 7 was rolled, players with >7 cards must discard
	ROBBER,             # Player must move the robber (after 7 or knight)
	ROAD_BUILDING,      # Free road placement(s) from Road Building dev card
}

enum DevCard {
	KNIGHT,
	VICTORY_POINT,
	MONOPOLY,
	YEAR_OF_PLENTY,
	ROAD_BUILDING,
}


# ---------------------------------------------------------------------------
# DATA STRUCTURES
# ---------------------------------------------------------------------------

## Hex: one tile on the board.
class Hex:
	var id: int = -1              # Stable index 0..18
	var axial_q: int = 0          # Axial coordinate q
	var axial_r: int = 0          # Axial coordinate r
	var resource: String = ""     # "wood", "brick", "sheep", "wheat", "ore", "desert"
	var token: int = 0            # Dice number (0 for desert)
	var has_robber: bool = false  # Whether the robber sits on this hex

	func _init(q: int = 0, r: int = 0, res: String = "", tok: int = 0) -> void:
		axial_q = q
		axial_r = r
		resource = res
		token = tok

	func _to_string() -> String:
		return "Hex(%d,%d %s %d%s)" % [axial_q, axial_r, resource, token,
			" ROBBER" if has_robber else ""]

	func clone() -> Hex:
		var c := Hex.new(axial_q, axial_r, resource, token)
		c.id = id
		c.has_robber = has_robber
		return c


## Vertex: a corner where settlements / cities are placed.
class Vertex:
	var id: int = -1              # Stable index 0..53
	var owner_id: int = -1        # -1 = unoccupied, 0..3 = player index
	var is_city: bool = false     # false = settlement, true = city
	var adjacent_hex_indices: Array[int] = []  # Indices into BoardPosition.hexes
	var port: String = ""         # "" = no port, "3:1" = generic, or specific resource

	func _init(vid: int = -1) -> void:
		id = vid

	func is_built() -> bool:
		return owner_id >= 0

	func _to_string() -> String:
		if owner_id < 0:
			return "Vertex(%d empty)" % id
		return "Vertex(%d P%d %s)" % [id, owner_id, "city" if is_city else "settlement"]

	func clone() -> Vertex:
		var c := Vertex.new(id)
		c.owner_id = owner_id
		c.is_city = is_city
		c.adjacent_hex_indices = adjacent_hex_indices.duplicate()
		c.port = port
		return c


## Road: an edge between two vertices.
class Road:
	var id: int = -1              # Stable index 0..71
	var owner_id: int = -1        # -1 = unoccupied, 0..3 = player index
	var vertex_a_id: int = -1     # Index into BoardPosition.vertices
	var vertex_b_id: int = -1     # Index into BoardPosition.vertices

	func _init(rid: int = -1, va: int = -1, vb: int = -1) -> void:
		id = rid
		vertex_a_id = va
		vertex_b_id = vb

	func is_built() -> bool:
		return owner_id >= 0

	func _to_string() -> String:
		if owner_id < 0:
			return "Road(%d empty)" % id
		return "Road(%d P%d %d-%d)" % [id, owner_id, vertex_a_id, vertex_b_id]

	func clone() -> Road:
		var c := Road.new(id, vertex_a_id, vertex_b_id)
		c.owner_id = owner_id
		return c


## PlayerState: everything about one player.
class PlayerState:
	var resources: Dictionary = {}          # { "wood": int, ... }
	var settlements_built: int = 0
	var cities_built: int = 0
	var roads_built: int = 0
	var victory_points: int = 0            # From settlements + cities + dev cards
	var knights_played: int = 0
	var has_longest_road: bool = false
	var has_largest_army: bool = false

	# Development cards in hand (unplayed)
	var dev_cards: Dictionary = {
		DevCard.KNIGHT: 0,
		DevCard.VICTORY_POINT: 0,
		DevCard.MONOPOLY: 0,
		DevCard.YEAR_OF_PLENTY: 0,
		DevCard.ROAD_BUILDING: 0,
	}

	# Dev cards bought this turn but not yet playable (standard rule)
	var new_dev_cards: Dictionary = {
		DevCard.KNIGHT: 0,
		DevCard.VICTORY_POINT: 0,
		DevCard.MONOPOLY: 0,
		DevCard.YEAR_OF_PLENTY: 0,
		DevCard.ROAD_BUILDING: 0,
	}

	func _init() -> void:
		for r in RESOURCE_TYPES:
			resources[r] = 0

	func total_resources() -> int:
		var total := 0
		for r in RESOURCE_TYPES:
			total += resources[r]
		return total

	func total_dev_cards() -> int:
		var total := 0
		for k in dev_cards:
			total += dev_cards[k]
		return total

	func _to_string() -> String:
		return "State" # Not needed, but keeps class well-formed

	func clone() -> PlayerState:
		var c := PlayerState.new()
		for r in resources:
			c.resources[r] = resources[r]
		c.settlements_built = settlements_built
		c.cities_built = cities_built
		c.roads_built = roads_built
		c.victory_points = victory_points
		c.knights_played = knights_played
		c.has_longest_road = has_longest_road
		c.has_largest_army = has_largest_army
		for k in dev_cards:
			c.dev_cards[k] = dev_cards[k]
		for k in new_dev_cards:
			c.new_dev_cards[k] = new_dev_cards[k]
		return c


## BoardPosition: complete snapshot of the game state.
##
## This is the primary input to search(). It encodes everything variable
## about a game of Settlers of Catan from start to finish.
class BoardPosition:
	# --- Meta ---
	var num_players: int = 3
	var current_player: int = 0          # Whose turn it is
	var phase: Phase = Phase.SETUP_FORWARD
	var turn_number: int = 0             # Incremented each full round

	# --- Board ---
	var hexes: Array[Hex] = []           # Always 19 entries, fixed topology
	var vertices: Array[Vertex] = []     # Always 54 entries
	var roads: Array[Road] = []          # Always 72 entries

	# --- Topology key mappings (for integration with game.gd) ---
	# Maps pixel-key strings ("x_y") to vertex/road indices.
	# Populated by _initialize_board_topology.
	var vertex_key_to_id: Dictionary = {}
	var road_key_to_id: Dictionary = {}

	# --- Players ---
	var players: Array[PlayerState] = [] # Length = num_players

	# --- Development card deck ---
	var dev_deck_remaining: int = DECK_TOTAL  # Cards left in the draw pile

	# --- Setup tracking ---
	var setup_placements: int = 0        # How many setup actions completed so far
	var setup_last_vertex_id: int = -1   # Last settlement placed in setup (for road)

	# --- Road Building tracking ---
	var free_roads_remaining: int = 0    # From Road Building dev card

	# --- Discard tracking ---
	# Players who still need to discard (bitmask or array)
	var players_to_discard: Array[bool] = []  # true = this player still needs to discard

	# --- Largest Army tracking ---
	var largest_army_player: int = -1    # -1 = unclaimed
	var largest_army_size: int = 0       # Current threshold (starts at 2, then 3+)

	# --- Longest Road tracking ---
	var longest_road_player: int = -1    # -1 = unclaimed
	var longest_road_length: int = 0     # Current threshold (starts at 4, then 5+)

	# --- Dice ---
	var last_dice_roll: int = 0          # Result of the most recent roll (0 = none yet)
	var robber_player: int = -1          # Player who must move robber (set on 7 or knight, cleared after)

	func _init(players_count: int = 3) -> void:
		num_players = players_count
		players.resize(num_players)
		players_to_discard.resize(num_players)
		for i in range(num_players):
			players[i] = PlayerState.new()

	func _to_string() -> String:
		return "BoardPosition(P%d turn=%d phase=%d)" % [current_player, turn_number, phase]
	
	func clone() -> BoardPosition:
		var dupl = BoardPosition.new(num_players)
		dupl.current_player = current_player
		dupl.phase = phase
		dupl.turn_number = turn_number

		dupl.hexes.resize(hexes.size())
		for i in range(hexes.size()):
			dupl.hexes[i] = hexes[i].clone()

		dupl.vertices.resize(vertices.size())
		for i in range(vertices.size()):
			dupl.vertices[i] = vertices[i].clone()

		dupl.roads.resize(roads.size())
		for i in range(roads.size()):
			dupl.roads[i] = roads[i].clone()

		dupl.players.resize(players.size())
		for i in range(players.size()):
			dupl.players[i] = players[i].clone()

		dupl.dev_deck_remaining = dev_deck_remaining

		dupl.setup_placements = setup_placements
		dupl.setup_last_vertex_id = setup_last_vertex_id

		dupl.free_roads_remaining = free_roads_remaining

		dupl.players_to_discard = players_to_discard.duplicate()

		dupl.largest_army_player = largest_army_player
		dupl.largest_army_size = largest_army_size

		dupl.last_dice_roll = last_dice_roll
		dupl.robber_player = robber_player

		dupl.longest_road_player = longest_road_player
		dupl.longest_road_length = longest_road_length

		return dupl
	
	func generate_moves() -> Array[Move]:
		match phase:
			Phase.SETUP_FORWARD, Phase.SETUP_BACKWARD:
				return _movegen_setup()
			# Phase.ROLL:
				# Dice has been resolved before search is called, so this
				# phase should be transient. If we land here, just move on.
				# return _search_main(pos)
			Phase.DISCARD:
				return _movegen_discard()
			Phase.ROBBER:
				return _movegen_robber()
			Phase.ROAD_BUILDING:
				return _movegen_road_building()
			Phase.MAIN:
				return _movegen_main()
			_:
				return [Move.new(Move.Type.END_TURN)]
				
				
	func _movegen_setup() -> Array[Move]:
		# Setup: first place a settlement, then a road.
		if setup_last_vertex_id == -1:
			return _movegen_setup_settlement()
		else:
			return _movegen_setup_road()


	func _movegen_setup_settlement() -> Array[Move]:
		# TODO: evaluate best vertex (resource probability, port access, blocking)
		# For now, pick first legal vertex.
		var move_list : Array[Move] = []
		
		for v in vertices:
			if _is_valid_settlement_placement(v.id, true):
				var move := Move.new(Move.Type.SETTLEMENT)
				move.vertex_id = v.id
				move_list.append(move)

		return move_list

	func _movegen_setup_road() -> Array[Move]:
		# Must attach to the last settlement placed in setup.
		var anchor: int = setup_last_vertex_id
		var move_list: Array[Move] = []
		
		for r in roads:
			if r.owner_id == -1 and (r.vertex_a_id == anchor or r.vertex_b_id == anchor):
				var move := Move.new(Move.Type.ROAD)
				move.road_id = r.id
				move_list.append(move)

		return move_list

	func _movegen_main() -> Array[Move]:
		var moves: Array[Move] = []
		var pid := current_player
		var p := players[pid]

		# --- 1. Play development cards ---
		# Knights
		if p.dev_cards[DevCard.KNIGHT] > 0:
			moves.append(Move.new(Move.Type.PLAY_KNIGHT))
		# Monopoly — one move per resource type
		if p.dev_cards[DevCard.MONOPOLY] > 0:
			for res in RESOURCE_TYPES:
				var m := Move.new(Move.Type.PLAY_MONOPOLY)
				m.monopoly_resource = res
				moves.append(m)
		# Year of Plenty — all unordered pairs (including same resource twice)
		if p.dev_cards[DevCard.YEAR_OF_PLENTY] > 0:
			for i in range(RESOURCE_TYPES.size()):
				for j in range(i, RESOURCE_TYPES.size()):
					var m := Move.new(Move.Type.PLAY_YEAR_OF_PLENTY)
					m.yop_resource_1 = RESOURCE_TYPES[i]
					m.yop_resource_2 = RESOURCE_TYPES[j]
					moves.append(m)
		# Road Building
		if p.dev_cards[DevCard.ROAD_BUILDING] > 0:
			moves.append(Move.new(Move.Type.PLAY_ROAD_BUILDING))

		# --- 2. Build settlement ---
		for v in vertices:
			if _is_valid_settlement_placement(v.id, false):
				if _can_afford(pid, SETTLEMENT_COST):
					var m := Move.new(Move.Type.BUILD_SETTLEMENT)
					m.vertex_id = v.id
					moves.append(m)

		# --- 3. Build city ---
		for v in vertices:
			if v.owner_id == pid and not v.is_city:
				if _can_afford(pid, CITY_COST):
					var m := Move.new(Move.Type.BUILD_CITY)
					m.vertex_id = v.id
					moves.append(m)

		# --- 4. Build road ---
		for r in roads:
			if _is_valid_road_placement(r.id):
				if _can_afford(pid, ROAD_COST):
					var m := Move.new(Move.Type.BUILD_ROAD)
					m.road_id = r.id
					moves.append(m)

		# --- 5. Buy development card ---
		if dev_deck_remaining > 0:
			if _can_afford(pid, DEV_CARD_COST):
				moves.append(Move.new(Move.Type.BUY_DEV_CARD))

		# --- 6. Trade with bank ---
		# Determine the best trade ratio for each resource the player has
		for give_res in RESOURCE_TYPES:
			var give_ratio := _get_trade_ratio(pid, give_res)
			if p.resources[give_res] < give_ratio:
				continue
			for recv_res in RESOURCE_TYPES:
				if recv_res == give_res:
					continue
				var m := Move.new(Move.Type.TRADE_BANK)
				m.bank_give = give_res
				m.bank_receive = recv_res
				m.bank_give_amount = give_ratio
				moves.append(m)

		# --- 7. End turn (always available) ---
		moves.append(Move.new(Move.Type.END_TURN))

		return moves


	func _can_afford(pid: int, cost: Dictionary) -> bool:
		for r in cost:
			if cost[r] <= 0:
				continue
			if players[pid].resources[r] < cost[r]:
				return false
		return true


	func _get_trade_ratio(pid: int, resource: String) -> int:
		# Check if player has a 2:1 port for this resource
		for v in vertices:
			if v.owner_id == pid and v.port == resource:
				return 2
		# Check if player has a 3:1 port
		for v in vertices:
			if v.owner_id == pid and v.port == "3:1":
				return 3
		# Default 4:1
		return 4


	func _movegen_discard() -> Array[Move]:
		var pid := current_player
		var p := players[pid]
		var total := p.total_resources()
		if total <= 7:
			# Nothing to discard — shouldn't be in DISCARD phase, but handle gracefully
			return [Move.new(Move.Type.END_TURN)]
		var to_discard: int = total / 2
		var discard := _choose_discard(p, to_discard)
		var move := Move.new(Move.Type.DISCARD)
		move.discard_resources = discard
		return [move]


	func _movegen_robber() -> Array[Move]:
		# TODO: pick hex that hurts opponents most / helps self least, then steal
		# For now, move robber to first hex that isn't current robber hex and has opponents.
		for h in hexes:
			if h.has_robber:
				continue
			if h.resource == "desert":
				continue
			# Check if any opponent has a settlement/city adjacent
			var has_opponent := false
			for vid in _hex_vertex_ids(h):
				var v: Vertex = vertices[vid]
				if v.is_built() and v.owner_id != current_player:
					has_opponent = true
					break
			if has_opponent:
				var move := Move.new(Move.Type.MOVE_ROBBER)
				move.robber_hex_id = h.id
				# Steal from a random adjacent opponent
				for vid in _hex_vertex_ids(h):
					var v: Vertex = vertices[vid]
					if v.is_built() and v.owner_id != current_player:
						move.robber_steal_target = v.owner_id
						break
				return [move]
		# Fallback: just move to first non-robber hex
		for h in hexes:
			if not h.has_robber and h.resource != "desert":
				var move := Move.new(Move.Type.MOVE_ROBBER)
				move.robber_hex_id = h.id
				move.robber_steal_target = -1
				return [move]
		return [Move.new(Move.Type.END_TURN)]


	func _movegen_road_building() -> Array[Move]:
		if free_roads_remaining <= 0:
			return [Move.new(Move.Type.END_TURN)]
		# TODO: pick best free road
		var move_list: Array[Move] = []
		for r in roads:
			if _is_valid_road_placement(r.id):
				var move := Move.new(Move.Type.BUILD_ROAD)
				move.road_id = r.id
				move_list.append(move)
		return move_list

	func _choose_discard(p: PlayerState, count: int) -> Dictionary:
		var result: Dictionary = {}
		var remaining := count
		# Discard from most abundant resources first
		var sorted_res := RESOURCE_TYPES.duplicate()
		sorted_res.sort_custom(func(a: String, b: String) -> bool:
			return p.resources[a] > p.resources[b]
		)
		for r in sorted_res:
			if remaining <= 0:
				break
			var take := mini(p.resources[r], remaining)
			if take > 0:
				result[r] = take
				remaining -= take
		return result

	func _is_valid_settlement_placement(vertex_id: int, is_setup: bool) -> bool:
		var v: Vertex = vertices[vertex_id]
		if v.is_built():
			return false
		# Distance rule: no adjacent vertex can be built
		for r in roads:
			if r.vertex_a_id == vertex_id or r.vertex_b_id == vertex_id:
				var other_id: int = r.vertex_b_id if r.vertex_a_id == vertex_id else r.vertex_a_id
				if vertices[other_id].is_built():
					return false
		if is_setup:
			return true
		# Must be connected to own road
		var pid := current_player
		for r in roads:
			if r.owner_id != pid:
				continue
			if r.vertex_a_id == vertex_id or r.vertex_b_id == vertex_id:
				return true
		return false


	func _is_valid_road_placement(road_id: int) -> bool:
		var r: Road = roads[road_id]
		if r.is_built():
			return false
		var pid := current_player
		# Must connect to own settlement/city/road
		if vertices[r.vertex_a_id].owner_id == pid or vertices[r.vertex_b_id].owner_id == pid:
			return true
		# Or connect to own existing road
		for other in roads:
			if other.owner_id != pid:
				continue
			if other.id == road_id:
				continue
			if _roads_adjacent(r, other):
				return true
		return false


	func _roads_adjacent(a: Road, b: Road) -> bool:
		return (a.vertex_a_id == b.vertex_a_id or a.vertex_a_id == b.vertex_b_id
			or a.vertex_b_id == b.vertex_a_id or a.vertex_b_id == b.vertex_b_id)
			
	func _hex_vertex_ids(hex: Hex) -> Array[int]:
		# Return the vertex IDs adjacent to a given hex.
		var result: Array[int] = []
		for v in vertices:
			if v.adjacent_hex_indices.has(hex.id):
				result.append(v.id)
		return result


	# ---------------------------------------------------------------------------
	# MOVE APPLICATION
	# ---------------------------------------------------------------------------

	func _apply_settlement(vertex_id: int) -> void:
		var v: Vertex = vertices[vertex_id]
		var pid := current_player
		v.owner_id = pid
		v.is_city = false
		players[pid].settlements_built += 1
		players[pid].victory_points += SETTLEMENT_VICTORY_POINTS
		setup_last_vertex_id = vertex_id
		# In setup backward, give resources from adjacent hexes
		if phase == Phase.SETUP_BACKWARD:
			_give_setup_resources(vertex_id)
	func _apply_road(road_id: int) -> void:
		var r: Road = roads[road_id]
		var pid := current_player
		r.owner_id = pid
		players[pid].roads_built += 1
		setup_last_vertex_id = -1
		setup_placements += 1
		
		# Advance setup phase
		var total_setup_steps: int = num_players * 2
		if setup_placements >= total_setup_steps:
			phase = Phase.MAIN
		elif setup_placements >= num_players:
			phase = Phase.SETUP_BACKWARD
		else:
			phase = Phase.SETUP_FORWARD
		
		# Advance to next player
		if setup_placements < num_players:
			current_player = setup_placements
		else:
			current_player = num_players - 1 - (setup_placements - num_players)
	func _apply_build_settlement(vertex_id: int) -> void:
		var pid := current_player
		_pay_resources(pid, SETTLEMENT_COST)
		var v: Vertex = vertices[vertex_id]
		v.owner_id = pid
		v.is_city = false
		players[pid].settlements_built += 1
		players[pid].victory_points += SETTLEMENT_VICTORY_POINTS
	func _apply_build_city(vertex_id: int) -> void:
		var pid := current_player
		_pay_resources(pid, CITY_COST)
		var v: Vertex = vertices[vertex_id]
		v.is_city = true
		players[pid].settlements_built -= 1
		players[pid].cities_built += 1
		players[pid].victory_points += 1  # City gives +2 total, settlement already gave +1
	func _apply_build_road(road_id: int) -> void:
		var pid := current_player
		_pay_resources(pid, ROAD_COST)
		var r: Road = roads[road_id]
		r.owner_id = pid
		players[pid].roads_built += 1
		_check_longest_road()
	func _apply_buy_dev_card() -> void:
		var pid := current_player
		_pay_resources(pid, DEV_CARD_COST)
		# Draw a card (simplified — in full engine, track deck composition)
		players[pid].new_dev_cards[DevCard.KNIGHT] += 1  # Placeholder
		dev_deck_remaining -= 1
	func _apply_play_knight() -> void:
		var pid := current_player
		players[pid].dev_cards[DevCard.KNIGHT] -= 1
		players[pid].knights_played += 1
		_check_largest_army()
		# Knight triggers robber phase — current player must move robber
		robber_player = pid
		phase = Phase.ROBBER
	func _apply_play_monopoly(resource: String) -> void:
		var pid := current_player
		players[pid].dev_cards[DevCard.MONOPOLY] -= 1
		var total_taken := 0
		for i in range(num_players):
			if i == pid:
				continue
			var amount: int = players[i].resources[resource]
			players[i].resources[resource] -= amount
			total_taken += amount
		players[pid].resources[resource] += total_taken
	func _apply_play_year_of_plenty(res1: String, res2: String) -> void:
		var pid := current_player
		players[pid].dev_cards[DevCard.YEAR_OF_PLENTY] -= 1
		players[pid].resources[res1] += 1
		players[pid].resources[res2] += 1
	func _apply_play_road_building() -> void:
		var pid := current_player
		players[pid].dev_cards[DevCard.ROAD_BUILDING] -= 1
		free_roads_remaining = 2
		phase = Phase.ROAD_BUILDING
	func _apply_trade_bank(give: String, receive: String, give_amount: int) -> void:
		var pid := current_player
		players[pid].resources[give] -= give_amount
		players[pid].resources[receive] += 1
	func _apply_trade_player(target: int, give: Dictionary, receive: Dictionary) -> void:
		var pid := current_player
		for r in give:
			players[pid].resources[r] -= give[r]
			players[target].resources[r] += give[r]
		for r in receive:
			players[pid].resources[r] += receive[r]
			players[target].resources[r] -= receive[r]
	func _apply_move_robber(hex_id: int, steal_target: int) -> void:
		# Remove robber from current hex
		for h in hexes:
			h.has_robber = false
		hexes[hex_id].has_robber = true
		
		if steal_target >= 0 and players[steal_target].total_resources() > 0:
			# Steal a random resource (simplified — pick first available)
			for r in RESOURCE_TYPES:
				if players[steal_target].resources[r] > 0:
					players[steal_target].resources[r] -= 1
					players[current_player].resources[r] += 1
					break
		
		# Clear the robber tracker — robber has been placed
		robber_player = -1
		
		# Return to main phase (or road building if that was interrupted)
		if free_roads_remaining > 0:
			phase = Phase.ROAD_BUILDING
		else:
			phase = Phase.MAIN
	func _apply_discard(discard: Dictionary) -> void:
		var pid := current_player
		for r in discard:
			players[pid].resources[r] -= discard[r]
		players_to_discard[pid] = false
		
		# Check if all players have discarded
		var all_done := true
		for i in range(num_players):
			if players_to_discard[i]:
				all_done = false
				# Move to next player who needs to discard
				current_player = i
				break
		if all_done:
			phase = Phase.ROBBER
			current_player = robber_player  # Return control to the roller
	func _apply_end_turn() -> void:
		# Merge new dev cards into playable hand
		var pid := current_player
		for k in players[pid].new_dev_cards:
			players[pid].dev_cards[k] += players[pid].new_dev_cards[k]
			players[pid].new_dev_cards[k] = 0
		
		# Advance to next player
		current_player = (current_player + 1) % num_players
		if current_player == 0:
			turn_number += 1
		
		# Roll dice for the new player
		var roll: int = _roll_dice()
		last_dice_roll = roll
		
		if roll == 7:
			# 7 triggers discard phase first.
			# pos.current_player is the player who just rolled — remember them.
			robber_player = current_player
			_initiate_discard_phase()
			# If no one actually needs to discard, go straight to robber
			var any_discard := false
			for i in range(num_players):
				if players_to_discard[i]:
					any_discard = true
					break
			if not any_discard:
				phase = Phase.ROBBER
				current_player = robber_player
		else:
			# Distribute resources
			_distribute_resources(roll)
			phase = Phase.MAIN
		
		
	func _roll_dice() -> int:
		# Roll two six-sided dice and return the sum.
		return randi_range(1, 6) + randi_range(1, 6)
	func _distribute_resources(roll: int) -> void:
		# For every hex matching the roll number that does NOT have the robber,
		# give 1 resource per adjacent settlement (2 per city) of the hex type
		# to the owning player.
		for hex in hexes:
			if hex.token != roll:
				continue
			if hex.has_robber:
				continue
			if hex.resource == "desert":
				continue
			# Find all vertices adjacent to this hex
			for vid in _hex_vertex_ids(hex):
				var v: Vertex = vertices[vid]
				if not v.is_built():
					continue
				var amount: int = 2 if v.is_city else 1
				players[v.owner_id].resources[hex.resource] += amount
	func _initiate_discard_phase() -> void:
		# Mark every player with more than 7 cards as needing to discard.
		# The discard phase starts with the first such player (lowest index).
		for i in range(num_players):
			players_to_discard[i] = players[i].total_resources() > 7
		# Find the first player who needs to discard
		for i in range(num_players):
			if players_to_discard[i]:
				current_player = i
				break
		phase = Phase.DISCARD
	# ---------------------------------------------------------------------------

	# ---------------------------------------------------------------------------
	# RESOURCE / ECONOMY HELPERS
	# ---------------------------------------------------------------------------

	func _pay_resources(pid: int, cost: Dictionary) -> void:
		for r in cost:
			players[pid].resources[r] -= cost[r]
	func _give_setup_resources(vertex_id: int) -> void:
		var pid := current_player
		var v: Vertex = vertices[vertex_id]
		for hex_id in v.adjacent_hex_indices:
			var hex: Hex = hexes[hex_id]
			if hex.resource != "desert":
				players[pid].resources[hex.resource] += 1
	# ---------------------------------------------------------------------------

	# ---------------------------------------------------------------------------
	# LONGEST ROAD / LARGEST ARMY
	# ---------------------------------------------------------------------------

	func _check_longest_road() -> void:
		var pid := current_player
		var length := _compute_longest_road(pid)
		if length > longest_road_length and length >= 5:
			# Revoke previous holder
			if longest_road_player >= 0:
				players[longest_road_player].has_longest_road = false
				players[longest_road_player].victory_points -= 2
			longest_road_player = pid
			longest_road_length = length
			players[pid].has_longest_road = true
			players[pid].victory_points += 2
	func _compute_longest_road(pid: int) -> int:
		# Build adjacency of player-owned roads, then DFS for longest path.
		# Simplified: return count of roads as upper bound.
		# A proper implementation would do DFS on the road graph.
		var max_length := 0
		var player_road_ends: Dictionary = {}  # vertex_id -> list of connected road vertex_ids
		for r in roads:
			if r.owner_id == pid:
				if not player_road_ends.has(r.vertex_a_id):
					player_road_ends[r.vertex_a_id] = []
				if not player_road_ends.has(r.vertex_b_id):
					player_road_ends[r.vertex_b_id] = []
				player_road_ends[r.vertex_a_id].append(r.vertex_b_id)
				player_road_ends[r.vertex_b_id].append(r.vertex_a_id)
		
		for start_vid in player_road_ends:
			max_length = max(max_length, _dfs_longest_road(player_road_ends, start_vid, {}))
		return max_length
		
		
	func _dfs_longest_road(adj: Dictionary, current: int, visited_edges: Dictionary) -> int:
		var best := 0
		if not adj.has(current):
			return 0
		for next_vid in adj[current]:
			var edge_key := _edge_key(current, next_vid)
			if visited_edges.has(edge_key):
				continue
			var new_visited = visited_edges.duplicate()
			new_visited[edge_key] = true
			best = max(best, 1 + _dfs_longest_road(adj, next_vid, new_visited))
		return best
		
		
	func _edge_key(a: int, b: int) -> int:
		if a < b:
			return a * 1000 + b
		return b * 1000 + a
	func _check_largest_army() -> void:
		var pid := current_player
		if players[pid].knights_played > largest_army_size and players[pid].knights_played >= 3:
			if largest_army_player >= 0:
				players[largest_army_player].has_largest_army = false
				players[largest_army_player].victory_points -= 2
			largest_army_player = pid
			largest_army_size = players[pid].knights_played
			players[pid].has_largest_army = true
			players[pid].victory_points += 2
	# ---------------------------------------------------------------------------
## Move: encodes any single action a player can take.
##
## This is the return type of search(). Exactly one field should be set;
## all others are default/empty to indicate "not this kind of move".
class Move:
	enum Type {
		# Setup
		SETTLEMENT,          # Place a settlement during setup
		ROAD,                # Place a road during setup

		# Main phase
		BUILD_SETTLEMENT,    # Build a settlement (costs resources)
		BUILD_CITY,          # Upgrade settlement to city
		BUILD_ROAD,          # Build a road
		BUY_DEV_CARD,        # Purchase a development card
		PLAY_KNIGHT,         # Play a knight card
		PLAY_MONOPOLY,       # Play monopoly (specify resource to take)
		PLAY_YEAR_OF_PLENTY, # Play year of plenty (specify 2 resources)
		PLAY_ROAD_BUILDING,  # Play road building (triggers free roads)
		TRADE_BANK,          # Trade 4:1 (or port ratio) with the bank
		TRADE_PLAYER,        # Propose a trade with another player
		MOVE_ROBBER,         # Move the robber to a hex
		DISCARD,             # Discard cards after a 7
		END_TURN,            # End the current turn
	}

	var type: Type = Type.END_TURN

	# --- Parameters (interpretation depends on type) ---

	# SETTLEMENT / BUILD_SETTLEMENT / BUILD_CITY
	var vertex_id: int = -1

	# ROAD / BUILD_ROAD
	var road_id: int = -1

	# PLAY_MONOPOLY
	var monopoly_resource: String = ""

	# PLAY_YEAR_OF_PLENTY — two resources (can be the same)
	var yop_resource_1: String = ""
	var yop_resource_2: String = ""

	# TRADE_BANK
	var bank_give: String = ""
	var bank_receive: String = ""
	var bank_give_amount: int = 4   # 4 for generic, 3 for 3:1 port, 2 for 2:1 port

	# TRADE_PLAYER
	var trade_target_player: int = -1
	var trade_give: Dictionary = {}   # { "wood": 2, ... }
	var trade_receive: Dictionary = {}

	# MOVE_ROBBER
	var robber_hex_id: int = -1
	var robber_steal_target: int = -1  # Player to steal from (-1 = none)

	# DISCARD
	var discard_resources: Dictionary = {}  # { "wood": 2, ... }

	func _init(move_type: Type = Type.END_TURN) -> void:
		type = move_type

	func _to_string() -> String:
		match type:
			Type.SETTLEMENT:
				return "Move(SETTLEMENT v%d)" % vertex_id
			Type.ROAD:
				return "Move(ROAD r%d)" % road_id
			Type.BUILD_SETTLEMENT:
				return "Move(BUILD_SETTLEMENT v%d)" % vertex_id
			Type.BUILD_CITY:
				return "Move(BUILD_CITY v%d)" % vertex_id
			Type.BUILD_ROAD:
				return "Move(BUILD_ROAD r%d)" % road_id
			Type.BUY_DEV_CARD:
				return "Move(BUY_DEV_CARD)"
			Type.PLAY_KNIGHT:
				return "Move(PLAY_KNIGHT)"
			Type.PLAY_MONOPOLY:
				return "Move(PLAY_MONOPOLY %s)" % monopoly_resource
			Type.PLAY_YEAR_OF_PLENTY:
				return "Move(PLAY_YEAR_OF_PLENTY %s %s)" % [yop_resource_1, yop_resource_2]
			Type.PLAY_ROAD_BUILDING:
				return "Move(PLAY_ROAD_BUILDING)"
			Type.TRADE_BANK:
				return "Move(TRADE_BANK %d %s -> %s)" % [bank_give_amount, bank_give, bank_receive]
			Type.TRADE_PLAYER:
				return "Move(TRADE_PLAYER with P%d)" % trade_target_player
			Type.MOVE_ROBBER:
				return "Move(MOVE_ROBBER h%d steal_P%d)" % [robber_hex_id, robber_steal_target]
			Type.DISCARD:
				return "Move(DISCARD %s)" % str(discard_resources)
			Type.END_TURN:
				return "Move(END_TURN)"
			_:
				return "Move(UNKNOWN)"

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	pass


# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

## Initialize the engine for a new game with the given number of players.
func new_game(num_players: int = 3) -> BoardPosition:
	assert(num_players >= 2 and num_players <= MAX_PLAYERS,
		"num_players must be 2..%d" % MAX_PLAYERS)
	var board = BoardPosition.new(num_players)
	_initialize_board_topology(board)
	return board


## Return the best move for the current player given the board position.
## This is the primary interface: the game calls this, gets a Move back,
## applies it, and calls again if it's still the same player's turn.
func search(pos: BoardPosition) -> Move:
	var move_list : Array[Move] = pos.generate_moves()
	
	print("Lista ruchów:", move_list)
	var chosen = move_list.pick_random()
	print("Wybrany:", chosen)
	return chosen


## Apply a move to a board position, returning a new position.
## The engine uses this internally for look-ahead; the game can also use
## it to apply the returned move.
func apply_move(pos: BoardPosition, move: Move) -> BoardPosition:
	var new_board = pos.clone()
	_apply_move_to_board(new_board, move)
	return new_board


func _apply_move_to_board(b: BoardPosition, move: Move) -> void:
	match move.type:
		Move.Type.SETTLEMENT:
			b._apply_settlement(move.vertex_id)
		Move.Type.ROAD:
			b._apply_road(move.road_id)
		Move.Type.BUILD_SETTLEMENT:
			b._apply_build_settlement(move.vertex_id)
		Move.Type.BUILD_CITY:
			b._apply_build_city(move.vertex_id)
		Move.Type.BUILD_ROAD:
			b._apply_build_road(move.road_id)
		Move.Type.BUY_DEV_CARD:
			b._apply_buy_dev_card()
		Move.Type.PLAY_KNIGHT:
			b._apply_play_knight()
		Move.Type.PLAY_MONOPOLY:
			b._apply_play_monopoly(move.monopoly_resource)
		Move.Type.PLAY_YEAR_OF_PLENTY:
			b._apply_play_year_of_plenty(move.yop_resource_1, move.yop_resource_2)
		Move.Type.PLAY_ROAD_BUILDING:
			b._apply_play_road_building()
		Move.Type.TRADE_BANK:
			b._apply_trade_bank(move.bank_give, move.bank_receive, move.bank_give_amount)
		Move.Type.TRADE_PLAYER:
			b._apply_trade_player(move.trade_target_player, move.trade_give, move.trade_receive)
		Move.Type.MOVE_ROBBER:
			b._apply_move_robber(move.robber_hex_id, move.robber_steal_target)
		Move.Type.DISCARD:
			b._apply_discard(move.discard_resources)
		Move.Type.END_TURN:
			b._apply_end_turn()

# ---------------------------------------------------------------------------
# BOARD TOPOLOGY INITIALIZATION
# ---------------------------------------------------------------------------

## Set up the fixed 19-hex / 54-vertex / 72-road topology.
## This is called once in new_game(). The actual resource/token assignment
## and port placement is done by the game and fed back via BoardPosition.
func _initialize_board_topology(board_position: BoardPosition) -> void:
	var b := board_position;

	# --- Hexes (axial coordinates for radius-2 hex grid) ---
	var axial_coords: Array[Vector2i] = []
	for q in range(-2, 3):
		for r in range(-2, 3):
			if abs(q + r) <= 2:
				axial_coords.append(Vector2i(q, r))

	axial_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		# Sort by ring then angle for deterministic ordering
		var ra : int = max(abs(a.x), abs(a.y), abs(a.x + a.y))
		var rb : int = max(abs(b.x), abs(b.y), abs(b.x + b.y))
		if ra != rb:
			return ra < rb
		var aa := atan2(float(a.y), float(a.x))
		var ab := atan2(float(b.y), float(b.x))
		return aa < ab
	)

	for i in range(axial_coords.size()):
		var hex := Hex.new(axial_coords[i].x, axial_coords[i].y)
		hex.id = i
		b.hexes.append(hex)

	assert(b.hexes.size() == HEX_COUNT, "Expected %d hexes, got %d" % [HEX_COUNT, b.hexes.size()])

	# --- Resources and Tokens ---
	# Build a shuffled resource bag from HEX_RESOURCE_COUNTS
	var resource_bag: Array[String] = []
	for res in HEX_RESOURCE_COUNTS:
		for _i in range(HEX_RESOURCE_COUNTS[res]):
			resource_bag.append(res)
	resource_bag.shuffle()

	# Build a shuffled token bag from TOKEN_COUNTS
	var token_bag: Array[int] = []
	for tok in TOKEN_COUNTS:
		for _i in range(TOKEN_COUNTS[tok]):
			token_bag.append(tok)
	token_bag.shuffle()

	# Assign resources and tokens to hexes
	for i in range(b.hexes.size()):
		var res: String = resource_bag[i]
		b.hexes[i].resource = res
		if res == "desert":
			b.hexes[i].token = 0
			b.hexes[i].has_robber = true  # Robber starts on desert
		else:
			b.hexes[i].token = token_bag.pop_front()

	# --- Vertices and Roads ---
	# We discover vertices and roads by walking hex corners in pixel space.
	# Each hex has 6 corners; each corner is shared by up to 3 hexes.
	# We use pixel-space positions (rounded to ints) as keys for deduplication,
	# matching the approach used in game.gd.

	var vertex_key_to_id: Dictionary = {}
	var road_key_to_id: Dictionary = {}
	var vertex_adj_hex: Dictionary = {}   # vertex_id -> Array[hex_id]

	for hex_id in range(b.hexes.size()):
		var hex := b.hexes[hex_id]
		var hex_pixel_pos: Vector2 = _axial_to_pixel(hex.axial_q, hex.axial_r)
		# Pre-compute all 6 corner keys for this hex
		var corner_keys: Array[String] = []
		for i in range(6):
			var angle: float = deg_to_rad(60 * i)
			var corner_pos: Vector2 = hex_pixel_pos + Vector2(cos(angle), sin(angle)) * HEX_SIZE
			corner_keys.append(_pixel_key(corner_pos))

		# Create vertices (first pass)
		var corner_vids: Array[int] = []
		for i in range(6):
			var vkey: String = corner_keys[i]
			if not vertex_key_to_id.has(vkey):
				var vid: int = vertex_key_to_id.size()
				vertex_key_to_id[vkey] = vid
				var v := Vertex.new(vid)
				b.vertices.append(v)
				vertex_adj_hex[vid] = []
			var vid: int = vertex_key_to_id[vkey]
			corner_vids.append(vid)
			vertex_adj_hex[vid].append(hex_id)

		# Create roads (second pass)
		for i in range(6):
			var vkey: String = corner_keys[i]
			var next_vkey: String = corner_keys[(i + 1) % 6]
			var rk: String = _road_key_from_vertex_keys(vkey, next_vkey)
			if not road_key_to_id.has(rk):
				var rid: int = road_key_to_id.size()
				road_key_to_id[rk] = rid
				b.roads.append(Road.new(rid, -1, -1))
			var rid: int = road_key_to_id[rk]
			var road: Road = b.roads[rid]
			if road.vertex_a_id == -1:
				road.vertex_a_id = corner_vids[i]
				road.vertex_b_id = corner_vids[(i + 1) % 6]

	# Fill in vertex adjacent hex indices
	for vid in range(b.vertices.size()):
		var arr: Array[int] = []
		for hex_id in vertex_adj_hex[vid]:
			arr.append(hex_id)
		b.vertices[vid].adjacent_hex_indices = arr

	assert(b.vertices.size() == VERTEX_COUNT, "Expected %d vertices, got %d" % [VERTEX_COUNT, b.vertices.size()])
	assert(b.roads.size() == ROAD_COUNT, "Expected %d roads, got %d" % [ROAD_COUNT, b.roads.size()])

	# --- Development deck ---
	b.dev_deck_remaining = DECK_TOTAL


## Convert axial hex coordinates to pixel-space position.
## Matches game.gd's axial_to_world (without board_offset).
func _axial_to_pixel(q: int, r: int) -> Vector2:
	var x: float = HEX_SIZE * (3.0 / 2.0 * q)
	var y: float = HEX_SIZE * (sqrt(3) / 2.0 * q + sqrt(3) * r)
	return Vector2(x, y)


## Generate a deduplication key from a pixel-space position.
## Matches game.gd's get_vertex_key.
func _pixel_key(pos: Vector2) -> String:
	return "%d_%d" % [int(round(pos.x)), int(round(pos.y))]


## Generate a canonical road key from two vertex keys.
func _road_key_from_vertex_keys(ka: String, kb: String) -> String:
	if ka > kb:
		return kb + "_" + ka
	return ka + "_" + kb

# ---------------------------------------------------------------------------
# UTILITY
# ---------------------------------------------------------------------------

## Create a BoardPosition from the current game.gd state.
## This is the adapter function the game calls to convert its visual state
## into the engine's internal representation before calling search().
func from_game_state(game_node: Node) -> BoardPosition:
	var g := game_node
	var num_players: int = g.player_count
	var pos := BoardPosition.new(num_players)
	_initialize_board_topology(pos)

	# --- Hexes: match by axial coordinates ---
	# game.gd stores hex_infos with axial coords; engine stores hexes by id.
	# Build a map from (q,r) → engine hex id.
	var axial_to_hex_id: Dictionary = {}
	for i in range(pos.hexes.size()):
		var key := "%d_%d" % [pos.hexes[i].axial_q, pos.hexes[i].axial_r]
		axial_to_hex_id[key] = i

	# Copy hex resources, tokens, and robber from game.gd hex_infos.
	for hex_info in g.hex_infos:
		var hq: int = hex_info["axial_q"] if hex_info.has("axial_q") else _pixel_to_axial_q(hex_info["position"] - g.board_offset)
		var hr: int = hex_info["axial_r"] if hex_info.has("axial_r") else _pixel_to_axial_r(hex_info["position"] - g.board_offset)
		var key := "%d_%d" % [hq, hr]
		if not axial_to_hex_id.has(key):
			# Fallback: find closest hex by pixel distance
			var best_id := -1
			var best_dist := INF
			for i in range(pos.hexes.size()):
				var hp := _axial_to_pixel(pos.hexes[i].axial_q, pos.hexes[i].axial_r)
				var dp: float = hp.distance_to(hex_info["position"] - g.board_offset)
				if dp < best_dist:
					best_dist = dp
					best_id = i
			if best_id >= 0:
				axial_to_hex_id[key] = best_id
		if axial_to_hex_id.has(key):
			var hid: int = axial_to_hex_id[key]
			pos.hexes[hid].resource = hex_info["resource_type"]
			pos.hexes[hid].token = hex_info["number"]
			pos.hexes[hid].has_robber = hex_info.get("has_robber", false)

	# --- Vertices: match by pixel-space key ---
	# game.gd uses string pixel keys; engine uses integer vertex IDs.
	# Build a map from pixel key → engine vertex id.
	var pixel_key_to_vid: Dictionary = {}
	for i in range(pos.vertices.size()):
		var vkey := _get_vertex_pixel_key(pos, i)
		pixel_key_to_vid[vkey] = i

	# Copy vertex ownership from game.gd's vertices_by_key.
	for vkey in g.vertices_by_key:
		var visual_vertex = g.vertices_by_key[vkey]
		if pixel_key_to_vid.has(vkey):
			var vid: int = pixel_key_to_vid[vkey]
			pos.vertices[vid].owner_id = visual_vertex.owner_id
			pos.vertices[vid].is_city = visual_vertex.is_city

	# --- Roads: match by endpoint pixel keys ---
	# game.gd roads_by_key uses sorted vertex key pairs.
	# engine roads use integer vertex IDs.
	for rk in g.roads_by_key:
		var visual_road = g.roads_by_key[rk]
		# Find the engine road with matching endpoint vertices
		for rid in range(pos.roads.size()):
			var road = pos.roads[rid]
			if road.owner_id != -1:
				continue  # already assigned
			var va_key := _get_vertex_pixel_key(pos, road.vertex_a_id)
			var vb_key := _get_vertex_pixel_key(pos, road.vertex_b_id)
			var engine_rk := _road_key_from_vertex_keys(va_key, vb_key)
			if engine_rk == rk:
				road.owner_id = visual_road.owner_id
				break

	# --- Player state ---
	for pid in range(num_players):
		pos.players[pid].resources = g.player_resources[pid].duplicate()
		pos.players[pid].victory_points = g.victory_points[pid]
		pos.players[pid].settlements_built = g.player_settlement_counts[pid]
		pos.players[pid].roads_built = g.player_road_counts[pid]
		pos.players[pid].cities_built = g.player_city_counts[pid]

	# --- Phase and turn tracking ---
	pos.current_player = g.current_player_index
	pos.turn_number = 0  # TODO: track in game.gd if needed

	if g.game_over:
		pos.phase = Phase.MAIN  # terminal; no moves needed
	elif g.waiting_for_robber:
		pos.phase = Phase.ROBBER
		pos.robber_player = g.current_player_index
	elif g.setup_phase:
		# Determine setup sub-phase from setup_step
		# pos.setup_step = g.setup_step
		# pos.setup_waiting_for_road = g.setup_waiting_for_road
		if g.setup_last_vertex != null:
			# Find the engine vertex id matching the visual vertex
			for vid in range(pos.vertices.size()):
				if pos.vertices[vid].owner_id == g.setup_last_vertex.owner_id:
					# Additional check: same position
					var vkey := _get_vertex_pixel_key(pos, vid)
					if g.vertices_by_key.has(vkey) and g.vertices_by_key[vkey] == g.setup_last_vertex:
						pos.setup_last_vertex_id = vid
						break
		# Count completed setup placements
		pos.setup_placements = g.setup_step
		var total_setup_steps: int = num_players * 2
		if g.setup_step >= total_setup_steps:
			pos.phase = Phase.MAIN
		elif g.setup_step >= num_players:
			pos.phase = Phase.SETUP_BACKWARD
		else:
			pos.phase = Phase.SETUP_FORWARD
	else:
		pos.phase = Phase.MAIN

	# --- Longest road / Largest army ---
	pos.longest_road_player = g.longest_road_owner
	pos.longest_road_length = g.longest_road_length

	return pos


## Helper: get the pixel-space key for an engine vertex.
func _get_vertex_pixel_key(pos: BoardPosition, vid: int) -> String:
	# Reconstruct the vertex pixel position from its adjacent hexes.
	var v: Vertex = pos.vertices[vid]
	if v.adjacent_hex_indices.size() == 0:
		return ""
	# Use the first adjacent hex to compute the pixel position.
	# We need to find which corner of that hex corresponds to this vertex.
	var hex_id: int = v.adjacent_hex_indices[0]
	var hex: Hex = pos.hexes[hex_id]
	var hex_pixel: Vector2 = _axial_to_pixel(hex.axial_q, hex.axial_r)
	# Check all 6 corners of this hex to find one matching this vertex
	for i in range(6):
		var angle: float = deg_to_rad(60 * i)
		var corner: Vector2 = hex_pixel + Vector2(cos(angle), sin(angle)) * HEX_SIZE
		var ckey := _pixel_key(corner)
		# Check if this corner key maps to the same vertex
		# by checking if any adjacent hex of this corner also has this vertex
		var matches := true
		for adj_hid in v.adjacent_hex_indices:
			var adj_hex: Hex = pos.hexes[adj_hid]
			var adj_pixel: Vector2 = _axial_to_pixel(adj_hex.axial_q, adj_hex.axial_r)
			var found := false
			for j in range(6):
				var a_angle: float = deg_to_rad(60 * j)
				var a_corner: Vector2 = adj_pixel + Vector2(cos(a_angle), sin(a_angle)) * HEX_SIZE
				if _pixel_key(a_corner) == ckey:
					found = true
					break
			if not found:
				matches = false
				break
		if matches:
			return ckey
	return ""


## Helper: convert pixel position back to axial q coordinate (approximate).
func _pixel_to_axial_q(pixel: Vector2) -> int:
	return int(round(pixel.x / (HEX_SIZE * 3.0 / 2.0)))


## Helper: convert pixel position back to axial r coordinate (approximate).
func _pixel_to_axial_r(pixel: Vector2) -> int:
	var q := _pixel_to_axial_q(pixel)
	return int(round((pixel.y - HEX_SIZE * sqrt(3) / 2.0 * q) / (HEX_SIZE * sqrt(3))))



## Convert a Move into game.gd actions.
## This is the adapter function the game calls to apply the engine's move.
func to_game_action(move: Move) -> Dictionary:
	# TODO: return a dictionary the game can interpret
	return {
		"type": move.type,
		"vertex_id": move.vertex_id,
		"road_id": move.road_id,
	}
