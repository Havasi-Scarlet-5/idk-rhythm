class_name Gameplay extends Node2D

@onready var strum_line:StrumLine = $StrumLine
@onready var scripts = $Scripts
@onready var tracks = $Tracks
@onready var hit_info = $HitInfo
@onready var score_info = $AnchorWorkaround/ScoreInfo
@onready var anchor_workaround = $AnchorWorkaround

@onready var health_bar = $ColorRect/Health
@onready var time_bar = $ColorRect/Time

@export var ms_gradient:Gradient = Gradient.new()
@export var hp_gradient:Gradient = Gradient.new()

static var song_folder:String = "mismatch"
static var chart:Chart
var first_track:AudioStreamPlayer
var combo:int = 0

var score:int = 0
var misses:int = 0
var health:float = 0.5
var length:float = 0

var ms_sum:float = 0
var ms_calc:float = 0
var passed_notes:int = 0

var queued_index:int = 0
var event_index:int = 0

var events:Array[Array] = []
@onready var strumlines:Array[StrumLine] = [strum_line]

func _ready():
	Conductor.bpm = chart.bpm
	Conductor.crochet = 60 / chart.bpm
	Conductor.bpm_changes = chart.bpm_changes
	Conductor.quant_offset = chart.song_offset

	Conductor.cur_pos = -Conductor.crochet
	Conductor.float_beat = 0.0
	Conductor.cur_beat = 0
	
	for line in strumlines:
		line.speed = Config.get_opt("scroll", 2.5) if Config.get_opt("force_scroll", false) else chart.speed
	for script in Chart.get_scripts(song_folder):
		script.game = self
		scripts.add_child(script)
	
	for event in events:
		if event.size() < 3:
			event.append([])
		elif not (event[2] is Array):
			event[2] = []
	
	events.filter(func(event):
		return 	event[0] is float \
			and event[1] is Callable
	)
	events.sort_custom(func(a, b): return a[0] < b[0])
	
	await get_tree().create_timer(Conductor.crochet).timeout

	for track in Chart.get_tracks(song_folder):
		tracks.add_child(track)
		track.play()
	first_track = tracks.get_child(0)
	length = first_track.stream.get_length()
		
	Conductor.beat_hit.connect(beat_hit)
	call_scripts("song_start", [])

func beat_hit(beat):
	call_scripts("beat_hit", [beat])
	if abs(first_track.get_playback_position() - Conductor.cur_pos) >= 0.02:
		for track in tracks.get_children():
			track.seek(Conductor.cur_pos)

func _process(delta):
	while events.size() > event_index and events[event_index][0] <= Conductor.float_beat:
		var event = events[event_index]
		event[1].callv(event[2])
		event_index += 1
	
	var beat_progress = 1 - fmod(Conductor.float_beat, 1.0)
	anchor_workaround.scale.x = 1 + (beat_progress * beat_progress * 0.1)
	anchor_workaround.scale.y = anchor_workaround.scale.x
	
	hit_info.rotation = lerpf(hit_info.rotation, 0, delta * 7)
	hit_info.modulate.a -= delta * 3
	
	while chart.notes.size() > queued_index and chart.notes[queued_index].time - Conductor.cur_pos < 2:
		for line in strumlines:
			line.make_note(chart.notes[queued_index])
		queued_index += 1
		
	if Input.is_action_just_pressed("ui_text_submit"):
		get_tree().paused = true
		
		if scale.x == 0:
			scale.x = 0.01
		if scale.y == 0:
			scale.y = 0.01
			
		var menu = load("res://scenes/game/PauseMenu.tscn").instantiate()
		menu.position = -position
		menu.rotation = -rotation
		menu.scale /= scale
		add_child(menu)
		
	if first_track != null:
		time_bar.value = Conductor.cur_pos / length
		health_bar.value = lerpf(health_bar.value, health, delta * 3)
		health_bar.tint_progress = hp_gradient.sample(health_bar.value)

func _note_hit(note):
	combo += 1
	
	var ms = roundf((Conductor.cur_pos - note.hit_time) * 100000) * 0.01
	ms_sum += ms
	ms_calc += abs(ms)
	if ms < 0:
		hit_info.text = "< %s ms\nCombo: %s" % [ms, combo]
		hit_info.rotation_degrees = -10 * Config.get_opt("combo_tilt", 1.0)
	else:
		hit_info.text = "%s ms >\nCombo: %s" % [ms, combo]
		hit_info.rotation_degrees = 10 * Config.get_opt("combo_tilt", 1.0)
	
	ms *= 0.001
	var score_mult = 1 - abs(ms / strum_line.hit_window)
	score += 350 * score_mult + floori(5 * (combo / 20.0))
	health = minf(1.0, health + 0.015 * (score_mult - 0.25))
	update_score()
	
	hit_info.modulate = ms_gradient.sample(score_mult)
	hit_info.modulate.a = 1.5
	
	call_scripts("note_hit", [note])

func _note_miss(note):
	combo = 0
	score -= 10
	misses += 1
	ms_calc += strum_line.hit_window * 1000
	hit_info.text = "oops..."
	hit_info.rotation_degrees = (10 if hit_info.rotation < 0 else -10) * Config.get_opt("combo_tilt", 1.0)
	hit_info.modulate = Color(1, 0.15, 0.15, 1.5)
	health = maxf(0.0, health - 0.02)
	update_score()
	
	call_scripts("note_miss", [note])

func update_score():
	passed_notes += 1
	var av_ms = roundf(ms_sum / passed_notes * 100) * 0.01
	var acc_ms = ms_calc / passed_notes
	var acc = 100 - abs(roundf(acc_ms / (strum_line.hit_window * 1000) * 10000) * 0.01)
	score_info.text = "Score: %s\nMisses: %s\nAccuracy: %s%s\nAverage MS: %s" % [score, misses, acc, "%", av_ms]



func call_scripts(func_name:String, params:Array[Variant]):
	for script in scripts.get_children():
		if script.has_method(func_name):
			script.callv(func_name, params)
