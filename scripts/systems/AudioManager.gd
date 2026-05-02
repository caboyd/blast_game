extends Node

## Centralizes SFX; future UI calls `set_overall_volume` / `set_sfx_volume`.

const STREAM_DRILL: AudioStream = preload("res://audio/drill.wav")
const STREAM_DIRTMINE: AudioStream = preload("res://audio/dirtmine.wav")
const STREAM_DIRTFALL: AudioStream = preload("res://audio/dirtfall.wav")

const _DRILL_PEAK_DB := -10.0
const _DIRTMINE_PEAK_DB := -16.0
const _DIRTFALL_PEAK_DB := -12.0

const _DRILL_LINEAR_IDLE_MULT := 0.35 ## volume multiplier when idle
const _DRILL_VOLUME_SLEW := 24.0 ## units per second toward target linear

const _PITCH_LOW := 0.92
const _PITCH_HIGH := 1.08

const _DIRTMINE_CAP := 3
const _DIRTMINE_COOLDOWN_S := 0.04
const _DIRTFALL_CAP := 5
const _DIRTFALL_COOLDOWN_S := 0.03

var overall_volume := 1.0
var sfx_volume := 1.0

var _rng := RandomNumberGenerator.new()

var _drill_player: AudioStreamPlayer2D
var _drill_engaged := false
var _drill_biting := false
var _drill_world_pos := Vector2.ZERO
var _drill_linear_smooth := 0.0 ## post–peak-linear target smoothing

var _dirtmine_players: Array[AudioStreamPlayer2D] = []
var _dirtmine_start_unix: PackedFloat64Array = PackedFloat64Array()
var _dirtmine_next_allowed := 0.0

var _dirtfall_players: Array[AudioStreamPlayer2D] = []
var _dirtfall_start_unix: PackedFloat64Array = PackedFloat64Array()
var _dirtfall_next_allowed := 0.0

## When set, all 2D players live under this node (game SubViewport). Prevents root-viewport / letterbox mismatch.
var _world_audio_mount: Node2D = null
var _world_mount_exit_cb: Callable


func _ready() -> void:
	_world_mount_exit_cb = Callable(self, "_detach_world_mount_on_exit")
	_rng.randomize()
	set_process(true)
	_drill_player = AudioStreamPlayer2D.new()
	_drill_player.name = &"DrillLoop"
	add_child(_drill_player)
	_drill_player.stream = STREAM_DRILL
	_drill_player.volume_db = -80.0
	_drill_player.bus = &"Master"
	if not _drill_player.playing:
		_drill_player.play()
	_prep_pool(_dirtmine_players, _dirtmine_start_unix, STREAM_DIRTMINE, _DIRTMINE_CAP)
	_prep_pool(_dirtfall_players, _dirtfall_start_unix, STREAM_DIRTFALL, _DIRTFALL_CAP)


func _prep_pool(
	out_players: Array[AudioStreamPlayer2D],
	out_times: PackedFloat64Array,
	stream_res: AudioStream,
	count: int
) -> void:
	out_times.resize(count)
	for i in range(count):
		out_times[i] = -999.0
		var ap := AudioStreamPlayer2D.new()
		ap.name = &"%s_%s" % [stream_res.resource_path.get_file().get_basename(), i]
		ap.bus = &"Master"
		add_child(ap)
		ap.stream = stream_res
		out_players.push_back(ap)


func set_overall_volume(v: float) -> void:
	overall_volume = clampf(v, 0.0, 1.0)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)


## Reparent 2D SFX under `mount` (e.g. `MiningWorld`) so world pixel coords match the game SubViewport.
## Also reconnects automatically when `mount` exits the scene tree (`MiningWorld` before `Planet` root).
func bind_world_audio_mount(mount: Node2D) -> void:
	if _world_audio_mount != null and is_instance_valid(_world_audio_mount):
		var old_m: Node2D = _world_audio_mount
		if old_m.tree_exiting.is_connected(_world_mount_exit_cb):
			old_m.tree_exiting.disconnect(_world_mount_exit_cb)
	_world_audio_mount = mount
	var new_parent: Node = self
	if mount != null and is_instance_valid(mount):
		new_parent = mount as Node
		var m: Node = mount as Node
		if not m.tree_exiting.is_connected(_world_mount_exit_cb):
			m.tree_exiting.connect(_world_mount_exit_cb)
	_reparent_player_nodes(new_parent)


func _detach_world_mount_on_exit() -> void:
	bind_world_audio_mount(null)


func _reparent_player_nodes(new_parent: Node) -> void:
	if _drill_player != null and is_instance_valid(_drill_player):
		if _drill_player.get_parent() != new_parent:
			new_parent.add_child(_drill_player)
	for pl: AudioStreamPlayer2D in _dirtmine_players:
		if pl != null and is_instance_valid(pl) and pl.get_parent() != new_parent:
			new_parent.add_child(pl)
	for pl: AudioStreamPlayer2D in _dirtfall_players:
		if pl != null and is_instance_valid(pl) and pl.get_parent() != new_parent:
			new_parent.add_child(pl)


func set_drilling(active: bool, world_pos: Vector2, biting_terrain: bool = false) -> void:
	_drill_engaged = active
	_drill_world_pos = world_pos
	_drill_biting = biting_terrain


func play_dirt_mine(world_pos: Vector2) -> void:
	var now := _unix_time_s()
	if now < _dirtmine_next_allowed:
		return
	if _play_pooled(
		STREAM_DIRTMINE, world_pos, _DIRTMINE_PEAK_DB, _dirtmine_players, _dirtmine_start_unix
	):
		_dirtmine_next_allowed = now + _DIRTMINE_COOLDOWN_S


func play_dirt_fall(world_pos: Vector2) -> void:
	var now := _unix_time_s()
	if now < _dirtfall_next_allowed:
		return
	if _play_pooled(
		STREAM_DIRTFALL, world_pos, _DIRTFALL_PEAK_DB, _dirtfall_players, _dirtfall_start_unix
	):
		_dirtfall_next_allowed = now + _DIRTFALL_COOLDOWN_S


func _play_pooled(
	stream_res: AudioStream,
	world_pos: Vector2,
	peak_db: float,
	players: Array[AudioStreamPlayer2D],
	times_arr: PackedFloat64Array,
) -> bool:
	var now := _unix_time_s()
	var mute_db := linear_to_db(0.0001)

	var ix := _allocate_pool_voice(players, times_arr, now, mute_db)
	if ix < 0:
		return false
	var pl: AudioStreamPlayer2D = players[ix]
	pl.stop()
	pl.stream = stream_res
	pl.global_position = world_pos
	pl.pitch_scale = _rng.randf_range(_PITCH_LOW, _PITCH_HIGH)
	var comb := clampf(overall_volume * sfx_volume, 0.0, 1.0)
	var lin := db_to_linear(peak_db) * comb
	pl.volume_db = linear_to_db(maxf(lin, 1e-5))
	pl.play()
	times_arr[ix] = now
	return true


## Returns idle index or index of reused voice; minus one if aborted.
func _allocate_pool_voice(
	players: Array[AudioStreamPlayer2D],
	times_arr: PackedFloat64Array,
	_now: float,
	mute_db: float
) -> int:
	for i in players.size():
		if not players[i].playing:
			return i

	var softest_ix := -1
	var softest_lin := INF
	var oldest_ix := -1
	var oldest_t := INF
	for i in players.size():
		var dbv: float = players[i].volume_db
		var lin_i: float = db_to_linear(dbv)
		if lin_i < softest_lin:
			softest_lin = lin_i
			softest_ix = i
		var t0: float = times_arr[i]
		if t0 < oldest_t:
			oldest_t = t0
			oldest_ix = i
	var reuse := softest_ix
	if reuse < 0:
		return -1
	if oldest_ix >= 0 and oldest_t < times_arr[reuse]:
		reuse = oldest_ix
	var pl: AudioStreamPlayer2D = players[reuse]
	pl.volume_db = mute_db ## quietest steals get silenced briefly before reuse
	pl.stop()
	return reuse


func _unix_time_s() -> float:
	return float(Time.get_ticks_usec()) / 1_000_000.0


func _combined_linear_amp() -> float:
	return clampf(overall_volume * sfx_volume, 0.0, 1.0)


func _drill_target_peak_linear() -> float:
	var bite_mult := 1.0 if _drill_biting else _DRILL_LINEAR_IDLE_MULT
	return db_to_linear(_DRILL_PEAK_DB) * bite_mult * _combined_linear_amp()


func _process(delta: float) -> void:
	if _drill_player == null:
		return
	var tgt := 0.0 if not _drill_engaged else _drill_target_peak_linear()
	var a: float = 1.0 - exp(-_DRILL_VOLUME_SLEW * delta)
	_drill_linear_smooth = lerpf(_drill_linear_smooth, tgt, a)

	_drill_player.global_position = _drill_world_pos
	if _drill_linear_smooth <= 1e-6:
		_drill_player.volume_db = -80.0
	else:
		_drill_player.volume_db = linear_to_db(maxf(_drill_linear_smooth, 1e-8))

