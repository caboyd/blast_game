extends Node
## Batches mined payouts on planet2 by predicted spiral arrival windows (planet2-only node).

const GROUP := &"black_hole_currency_mgr"

@export var arrival_accel: float = 1200.0
@export var arrival_swirl_resistance: float = 1.3
@export var arrival_bucket_step_s: float = 0.1
@export_range(0.05, 2.0) var arrival_time_min_s: float = 0.2
@export_range(0.1, 8.0) var arrival_time_max_s: float = 4.0

var hole_world_position: Vector2 = Vector2.ZERO

var _currency_buckets: Dictionary = {} # float snapped deadline -> cumulative int amount
var _scratch_mature_keys: Array[float] = []

func _ready() -> void:
	add_to_group(GROUP)
	set_process(true)


func configure_hole_world_position(pos: Vector2) -> void:
	hole_world_position = pos


func get_arrival_time(spawn_pos: Vector2, hole_pos: Vector2) -> float:
	var dist := spawn_pos.distance_to(hole_pos)
	var travel_time := (pow(dist, 1.5) * arrival_swirl_resistance) / maxf(arrival_accel, 1.0)
	return clampf(travel_time, arrival_time_min_s, arrival_time_max_s)


func queue_mined_reward(amount: int, spawn_world: Vector2) -> void:
	if amount <= 0:
		return
	var now_msec := Time.get_ticks_msec()
	var now_s := float(now_msec) * 0.001
	var pay_deadline := now_s + get_arrival_time(spawn_world, hole_world_position)
	var key := snappedf(pay_deadline, arrival_bucket_step_s)
	_currency_buckets[key] = int(_currency_buckets.get(key, 0)) + amount


func _process(_delta: float) -> void:
	if _currency_buckets.is_empty():
		return
	var now_s := float(Time.get_ticks_msec()) * 0.001
	_scratch_mature_keys.clear()
	for k in _currency_buckets.keys():
		if float(k) <= now_s:
			_scratch_mature_keys.append(float(k))
	if _scratch_mature_keys.is_empty():
		return
	_scratch_mature_keys.sort()
	for mk in _scratch_mature_keys:
		var amt: int = int(_currency_buckets.get(mk, 0))
		_currency_buckets.erase(mk)
		if amt > 0:
			GameStatistics.add_mined_cell_reward(amt)
