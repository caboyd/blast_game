extends Node

## Centralizes SFX; future UI calls `set_overall_volume` / `set_sfx_volume`.

const STREAM_DRILL: AudioStream = preload("res://audio/drill.wav")
const STREAM_DRILL_BLOCK: AudioStream = preload("res://audio/dirtmine.wav")
const STREAM_BLOCK_POP: AudioStream = preload("res://audio/block_pop.wav")
const STREAM_DIRTFALL: AudioStream = preload("res://audio/dirtfall.wav")

const _DRILL_PEAK_DB := -8.0
const _DRILL_BLOCK_PEAK_DB := -16.0
const _BLOCK_POP_PEAK_DB := -36.0
const _DIRTFALL_LAYER_PEAK_DB := -2.0 ## layered with block_pop; tune for balance

const _DRILL_LINEAR_IDLE_MULT := 0.3 ## volume multiplier when idle
## First-order smoothing time constant (seconds): larger = **slower** transition toward target.
const _DRILL_VOLUME_ATTACK_TAU_S := 0.1
const _DRILL_VOLUME_RELEASE_TAU_S := 1.0

const _DRILL_BLOCK_LINEAR_IDLE_MULT := 0.0 ## dirt mine loop voices: silent when not biting terrain
const _DRILL_BLOCK_ATTACK_TAU_S := 0.1
const _DRILL_BLOCK_RELEASE_TAU_S := 0.8

const _PITCH_LOW := 1.0
const _PITCH_HIGH := 1.3

const _DRILL_BLOCK_CAP := 4
const _DRILL_BLOCK_COOLDOWN_S := 0.04
const _BLOCK_POP_CAP := 8
const _BLOCK_POP_COOLDOWN_S := 0.03

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
var _dirtmine_peak_linear: PackedFloat64Array = PackedFloat64Array()
var _dirtmine_linear_smooth: PackedFloat64Array = PackedFloat64Array()
var _dirtmine_next_allowed := 0.0

var _dirtfall_players: Array[AudioStreamPlayer2D] = []
var _dirtfall_start_unix: PackedFloat64Array = PackedFloat64Array()
var _dirtfall_layer_players: Array[AudioStreamPlayer2D] = []
var _dirtfall_layer_start_unix: PackedFloat64Array = PackedFloat64Array()
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
	_prep_pool(_dirtmine_players, _dirtmine_start_unix, STREAM_DRILL_BLOCK, _DRILL_BLOCK_CAP)
	_dirtmine_peak_linear.resize(_DRILL_BLOCK_CAP)
	_dirtmine_linear_smooth.resize(_DRILL_BLOCK_CAP)
	_prep_pool(_dirtfall_players, _dirtfall_start_unix, STREAM_BLOCK_POP, _BLOCK_POP_CAP)
	_prep_pool(_dirtfall_layer_players, _dirtfall_layer_start_unix, STREAM_DIRTFALL, _BLOCK_POP_CAP)


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
	if mount == null:
		stop_managed_world_audio()
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


## Stops drill + pooled dirt SFX immediately (called when leaving a mining scene / unbinding mount).
func stop_managed_world_audio() -> void:
	_drill_engaged = false
	_drill_biting = false
	_drill_linear_smooth = 0.0
	if _drill_player != null and is_instance_valid(_drill_player):
		_drill_player.volume_db = -80.0
	for i in _dirtmine_players.size():
		var pl: AudioStreamPlayer2D = _dirtmine_players[i]
		if pl != null and is_instance_valid(pl):
			pl.stop()
			if i < _dirtmine_peak_linear.size():
				_dirtmine_peak_linear[i] = 0.0
			if i < _dirtmine_linear_smooth.size():
				_dirtmine_linear_smooth[i] = 0.0
	for pl: AudioStreamPlayer2D in _dirtfall_players:
		if pl != null and is_instance_valid(pl):
			pl.stop()
	for pl: AudioStreamPlayer2D in _dirtfall_layer_players:
		if pl != null and is_instance_valid(pl):
			pl.stop()


func _reparent_player_nodes(new_parent: Node) -> void:
	if _drill_player != null and is_instance_valid(_drill_player):
		if _drill_player.get_parent() != new_parent:
			_drill_player.reparent(new_parent)
			if not _drill_player.playing:
				_drill_player.play()
	for pl: AudioStreamPlayer2D in _dirtmine_players:
		if pl != null and is_instance_valid(pl) and pl.get_parent() != new_parent:
			pl.reparent(new_parent)
	for pl: AudioStreamPlayer2D in _dirtfall_players:
		if pl != null and is_instance_valid(pl) and pl.get_parent() != new_parent:
			pl.reparent(new_parent)
	for pl: AudioStreamPlayer2D in _dirtfall_layer_players:
		if pl != null and is_instance_valid(pl) and pl.get_parent() != new_parent:
			pl.reparent(new_parent)


func set_drilling(active: bool, world_pos: Vector2, biting_terrain: bool = false) -> void:
	_drill_engaged = active
	_drill_world_pos = world_pos
	_drill_biting = biting_terrain


func play_dirt_mine(world_pos: Vector2) -> void:
	var now := _unix_time_s()
	if now < _dirtmine_next_allowed:
		return
	var ix := _play_pooled(
		STREAM_DRILL_BLOCK, world_pos, _DRILL_BLOCK_PEAK_DB, _dirtmine_players, _dirtmine_start_unix
	)
	if ix >= 0:
		_dirtmine_next_allowed = now + _DRILL_BLOCK_COOLDOWN_S
		var pl: AudioStreamPlayer2D = _dirtmine_players[ix]
		var lin: float = db_to_linear(pl.volume_db)
		_dirtmine_peak_linear[ix] = lin
		_dirtmine_linear_smooth[ix] = lin


func play_dirt_fall(world_pos: Vector2) -> void:
	var now := _unix_time_s()
	if now < _dirtfall_next_allowed:
		return
	var any := false
	if _play_pooled(
		STREAM_BLOCK_POP, world_pos, _BLOCK_POP_PEAK_DB, _dirtfall_players, _dirtfall_start_unix
	) >= 0:
		any = true
	if _play_pooled(
		STREAM_DIRTFALL, world_pos, _DIRTFALL_LAYER_PEAK_DB, _dirtfall_layer_players, _dirtfall_layer_start_unix
	) >= 0:
		any = true
	if any:
		_dirtfall_next_allowed = now + _BLOCK_POP_COOLDOWN_S


func _play_pooled(
	stream_res: AudioStream,
	world_pos: Vector2,
	peak_db: float,
	players: Array[AudioStreamPlayer2D],
	times_arr: PackedFloat64Array,
) -> int:
	var now := _unix_time_s()
	var mute_db := linear_to_db(0.0001)

	var ix := _allocate_pool_voice(players, times_arr, now, mute_db)
	if ix < 0:
		return -1
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
	return ix


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


func _smoothing_alpha(delta: float, tau_s: float) -> float:
	var tau := maxf(tau_s, 1e-9)
	return 1.0 - exp(-delta / tau)


func _process(delta: float) -> void:
	if _drill_player != null:
		var tgt_d := 0.0 if not _drill_engaged else _drill_target_peak_linear()
		var tau_drill: float = (
			_DRILL_VOLUME_ATTACK_TAU_S
			if tgt_d > _drill_linear_smooth
			else _DRILL_VOLUME_RELEASE_TAU_S
		)
		var a_drill: float = _smoothing_alpha(delta, tau_drill)
		_drill_linear_smooth = lerpf(_drill_linear_smooth, tgt_d, a_drill)
		_drill_player.global_position = _drill_world_pos
		if _drill_linear_smooth <= 1e-6:
			_drill_player.volume_db = -80.0
		else:
			_drill_player.volume_db = linear_to_db(maxf(_drill_linear_smooth, 1e-8))

	var block_bite_mult := 1.0 if (_drill_engaged and _drill_biting) else _DRILL_BLOCK_LINEAR_IDLE_MULT
	for i in _dirtmine_players.size():
		var pl_b: AudioStreamPlayer2D = _dirtmine_players[i]
		if pl_b == null or not is_instance_valid(pl_b):
			continue
		if not pl_b.playing:
			_dirtmine_linear_smooth[i] = 0.0
			_dirtmine_peak_linear[i] = 0.0
			continue
		var tgt_b := _dirtmine_peak_linear[i] * block_bite_mult
		var tau_b: float = (
			_DRILL_BLOCK_ATTACK_TAU_S
			if tgt_b > _dirtmine_linear_smooth[i]
			else _DRILL_BLOCK_RELEASE_TAU_S
		)
		var a_b: float = _smoothing_alpha(delta, tau_b)
		_dirtmine_linear_smooth[i] = lerpf(_dirtmine_linear_smooth[i], tgt_b, a_b)
		if _dirtmine_linear_smooth[i] <= 1e-6:
			pl_b.stop()
			pl_b.volume_db = -80.0
			_dirtmine_linear_smooth[i] = 0.0
			_dirtmine_peak_linear[i] = 0.0
		else:
			pl_b.volume_db = linear_to_db(maxf(_dirtmine_linear_smooth[i], 1e-8))
