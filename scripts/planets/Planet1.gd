extends PlanetBase

## Planet 1: dirt + stone-splat + sparse gold-vein generation, with one
## hand-placed "generation monument" landmark in chunk (0, 3) and a small set
## of tier-1 part pickups in/around the spawn chunk.

## Planet 1 “generation monument”: hollow 5×5 (non-solid shell) + ruby center cell.
const GENERATION_MONUMENT_CHUNK := Vector2i(0, 3)
const GENERATION_MONUMENT_CENTER_CELL := Vector2i(20, 100)
const GENERATION_MONUMENT_RADIUS_CELLS := 2
const _GENERATION_MONUMENT_SCRIPT: GDScript = preload("res://scripts/world/GenerationMonument.gd")

## Landmarks in absolute world cell coordinates (post-generation stamp).
const STATIC_CELLS: Array[Dictionary] = [
	{"cell": Vector2i(0, -10), "type": MiningWorld.TYPE_GOLD, "hp": 5},
]

const PRIMARY_MATERIAL_TYPE := MiningWorld.TYPE_DIRT

## Edit colors here (int keys = `MiningWorld.TYPE_*`). Omitted types use `MiningWorld.TYPE_COLOR` at runtime.
const CELL_MATERIAL_COLORS: Dictionary = {
	MiningWorld.TYPE_EMPTY: Color(0.0, 0.0, 0.0, 0.0),
	MiningWorld.TYPE_DIRT: Color(0.42, 0.28, 0.18, 1.0),
	MiningWorld.TYPE_STONE: Color(0.52, 0.52, 0.55, 1.0),
	MiningWorld.TYPE_GOLD: Color(1.0, 0.82, 0.2, 1.0),
	# Fuel shader uses this as its tint anchor; brown preserves the current look.
	MiningWorld.TYPE_FUEL: Color(0.22, 0.15, 0.10, 1.0),
	MiningWorld.TYPE_RUBY: Color(0.92, 0.18, 0.38, 1.0),
}

## Planet 1: only parts with `PartData.tier == 1` (`_t1` line). Tier 0 has no ground pickups.
const PART_PICKUP_DEFS: Array[Dictionary] = [
	{
		"pickup_id": &"planet1_part_fuel_tank_t1_i0",
		"part_id": &"part_fuel_tank_t1",
		"pickup_index": 0,
		"persistence": PartRegistry.PICKUP_PERSISTENCE_ONCE,
	},
	{
		"pickup_id": &"planet1_part_fuel_tank_t1_i1",
		"part_id": &"part_fuel_tank_t1",
		"pickup_index": 1,
		"persistence": PartRegistry.PICKUP_PERSISTENCE_ONCE,
	},
	{
		"pickup_id": &"planet1_part_drill_t1_i0",
		"part_id": &"part_drill_t1",
		"pickup_index": 0,
		"persistence": PartRegistry.PICKUP_PERSISTENCE_ONCE,
	},
	{
		"pickup_id": &"planet1_part_drill_t1_i1",
		"part_id": &"part_drill_t1",
		"pickup_index": 1,
		"persistence": PartRegistry.PICKUP_PERSISTENCE_ONCE,
	},
	{
		"pickup_id": &"planet1_part_treads_t1_i0",
		"part_id": &"part_treads_t1",
		"pickup_index": 0,
		"persistence": PartRegistry.PICKUP_PERSISTENCE_ONCE,
	},
	{
		"pickup_id": &"planet1_part_treads_t1_i1",
		"part_id": &"part_treads_t1",
		"pickup_index": 1,
		"persistence": PartRegistry.PICKUP_PERSISTENCE_ONCE,
	},
]

## Probability per cell during gold pass (after dirt + rock splats). Sparse by default.
@export_range(0.0, 1.0, 0.0001) var gold_density: float = 0.012

var _generation_monument: Node2D = null


func _cell_material_colors() -> Dictionary:
	return CELL_MATERIAL_COLORS


func _part_pickup_defs() -> Array[Dictionary]:
	return PART_PICKUP_DEFS


func _generate_mining_world_chunk(
	world: MiningWorld,
	chunk: Vector2i,
	rng: RandomNumberGenerator,
	chunk_data: Dictionary
) -> void:
	world.fill_chunk_with_type(chunk_data, MiningWorld.TYPE_DIRT)
	world.add_random_stone_splats_to_chunk(chunk_data, rng, 1, 3, 2, 5)
	world.add_gold_veins_to_chunk(chunk_data, rng, gold_density)
	if chunk != Vector2i.ZERO:
		var fuel_anchor := Vector2i(
			rng.randi_range(0, MiningWorld.CHUNK_SIZE - 2),
			rng.randi_range(0, MiningWorld.CHUNK_SIZE - 2)
		)
		world.stamp_fuel_cluster(chunk_data, fuel_anchor, Vector2i(2, 2))
	world.stamp_cell_overrides_for_chunk(chunk, STATIC_CELLS)
	if chunk == GENERATION_MONUMENT_CHUNK:
		world.stamp_square_shell_for_chunk(
			chunk,
			GENERATION_MONUMENT_CENTER_CELL,
			GENERATION_MONUMENT_RADIUS_CELLS,
			MiningWorld.TYPE_EMPTY,
			MiningWorld.TYPE_RUBY
		)


func _post_ship_spawn(_spawn_world: Vector2) -> void:
	_attach_generation_monument(_ship)


func _attach_generation_monument(ship: Node2D) -> void:
	if _generation_monument != null:
		return
	var ship_base := ship as ShipBase
	if ship_base == null:
		return
	_mining_world.ensure_chunk(GENERATION_MONUMENT_CHUNK)
	var cw: Vector2 = _mining_world.cell_center_world(GENERATION_MONUMENT_CENTER_CELL)
	var mon = _GENERATION_MONUMENT_SCRIPT.new()
	mon.name = "GenerationMonumentChunk02"
	mon.setup(ship_base, cw)
	_mining_world.add_child(mon)
	_generation_monument = mon
