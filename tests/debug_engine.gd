extends Node

func _ready():
    var engine = CatanEngine.new()
    
    # Mocking necessary game state for from_game_state
    # This might be tricky because of the GDScript dependencies, 
    # but I can try to simulate the dictionary structures.
    
    print("Testing board topology...")
    var pos = engine.new_game(2)
    print("Board generated with ", pos.hexes.size(), " hexes, ", pos.vertices.size(), " vertices, ", pos.roads.size(), " roads.")
    
    # Let's check some simple assumptions
    assert(pos.hexes.size() == 19)
    assert(pos.vertices.size() == 54)
    assert(pos.roads.size() == 72)
    print("Topology constraints satisfied.")
    
    # Debugging vertex keys
    var v0_key = engine._get_vertex_pixel_key(pos, 0)
    print("Vertex 0 key: ", v0_key)
    
    # Try re-mapping to ensure IDs are consistent
    # The main issue reported is "converting from the game state to the engine BoardPosition"
    
    # I suspect the issue might be in _initialize_board_topology not matching
    # exactly the order or keys generated in game.gd.
    
    # Let's list the vertex keys as the engine sees them:
    var vertex_keys = []
    for i in range(pos.vertices.size()):
        vertex_keys.append(engine._get_vertex_pixel_key(pos, i))
    print("Engine vertex keys sample (first 5): ", vertex_keys.slice(0, 5))
    
    # Compare with expected logic:
    # engine.gd _initialize_board_topology uses the same hex_size and board_offset logic?
    # Actually engine doesn't know about board_offset.
    
    get_tree().quit()

