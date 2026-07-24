extends Node
## Attached to BaccaratBoard (root node).
## Polls a mock HTTP endpoint, maintains the bead road history as the
## single source of truth, and renders it into the column-first grid:
## BeadRoadGrid/row-container/col{N}/row{N}

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
@export var endpoint_url: String = "http://127.0.0.1:8787/round"
@export var poll_interval_seconds: float = 2.5

const ROWS := 3  # fixed rows per column (row0, row1, row2)
const VALID_OUTCOMES := ["player", "banker", "tie"]

# ---------------------------------------------------------------------------
# NODE REFERENCES
# ---------------------------------------------------------------------------
@onready var http_request: HTTPRequest = $HTTPPoller/HTTPRequest
@onready var poll_timer: Timer = $HTTPPoller/Timer
@onready var bead_grid: Node = $BeadRoadGrid
@onready var row_container: Node = $"BeadRoadGrid/ScrollContainer/row-container"
@onready var status_label: Label = $StatusLabel
@onready var game_state: Node = $GameStateManager

# ---------------------------------------------------------------------------
# STATE (source of truth — independent of any network node's lifecycle)
# ---------------------------------------------------------------------------
var history: Array = []       # Array of {outcome, col, row}
var current_col: int = 0
var current_row: int = 0
var is_request_pending: bool = false
var consecutive_failures: int = 0


func _ready() -> void:
	http_request.timeout = 3.0
	http_request.request_completed.connect(_on_request_completed)
	poll_timer.wait_time = poll_interval_seconds
	poll_timer.timeout.connect(_on_poll_timer_timeout)

	set_status("Connecting...", Color.GRAY)
	poll_timer.start()


# ---------------------------------------------------------------------------
# POLLING
# ---------------------------------------------------------------------------
func _on_poll_timer_timeout() -> void:
	if is_request_pending:
		return  # never let requests overlap

	var err := http_request.request(endpoint_url)
	if err != OK:
		_on_poll_failed("Could not start request (err %d)" % err)
		return

	is_request_pending = true


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_request_pending = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_on_poll_failed("HTTP result=%d code=%d" % [result, response_code])
		return

	var text := body.get_string_from_utf8()
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		_on_poll_failed("Malformed JSON")
		return

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY or not data.has("outcome"):
		_on_poll_failed("Missing 'outcome' field")
		return

	var outcome := str(data["outcome"]).to_lower()
	if not VALID_OUTCOMES.has(outcome):
		_on_poll_failed("Unrecognized outcome: %s" % outcome)
		return

	consecutive_failures = 0
	set_status("Live", Color.GREEN)
	add_result(outcome)


func _on_poll_failed(reason: String) -> void:
	consecutive_failures += 1
	set_status("Connecting...", Color.GRAY)
	#set_status("Endpoint unreachable — retrying (%d)" % consecutive_failures, Color.ORANGE)
	push_warning("Poll failed: %s" % reason)
	# Deliberately does nothing to `history` — a failed poll can never
	# mutate or clear existing board state.


func set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# BEAD ROAD LOGIC
# ---------------------------------------------------------------------------
func add_result(outcome: String) -> void:
	if history.is_empty():
		current_col = 0
		current_row = 0
	else:
		var prev_outcome: String = history[-1]["outcome"]
		var column_is_full := current_row + 1 >= ROWS
		if outcome == prev_outcome and not column_is_full:
			current_row += 1
		else:
			current_col += 1
			current_row = 0

	history.append({"outcome": outcome, "col": current_col, "row": current_row})
	place_marker(current_col, current_row, outcome)


func get_col_node(col_index: int) -> Node:
	var col_name := "col%d" % col_index
	if row_container.has_node(col_name):
		return row_container.get_node(col_name)

	# New column needed — duplicate col0 as a template. It already
	# contains row0/row1/row2 as empty slot containers.
	var template: Node = row_container.get_node("col0")
	var new_col: Node = template.duplicate()
	new_col.name = col_name
	row_container.add_child(new_col)

	# Defensive: strip any markers that got copied along with the
	# template so a freshly created column always starts empty.
	for row_index in range(ROWS):
		var row_slot: Node = new_col.get_node("row%d" % row_index)
		for child in row_slot.get_children():
			child.queue_free()

	return new_col


func place_marker(col_index: int, row_index: int, outcome: String) -> void:
	var col_node: Node = get_col_node(col_index)
	var row_slot: Node = col_node.get_node("row%d" % row_index)

	# Defensive clear before placing, in case this slot was ever reused.
	for child in row_slot.get_children():
		child.queue_free()

	var marker := Panel.new()
	marker.custom_minimum_size = Vector2(28, 28)
	marker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = get_color_for_outcome(outcome)
	style.set_corner_radius_all(14)  # half of min size -> circular
	marker.add_theme_stylebox_override("panel", style)

	row_slot.add_child(marker)


func get_color_for_outcome(outcome: String) -> Color:
	match outcome:
		"player":
			return Color(0.2, 0.45, 1.0)   # blue
		"banker":
			return Color(0.95, 0.2, 0.2)   # red
		"tie":
			return Color(0.25, 0.8, 0.35)  # green
		_:
			return Color.WHITE


# ---------------------------------------------------------------------------
# OPTIONAL: manual reset for testing
# ---------------------------------------------------------------------------
func reset_board() -> void:
	history.clear()
	current_col = 0
	current_row = 0
	for col_node in row_container.get_children():
		if col_node.name != "col0":
			col_node.queue_free()
		else:
			for row_slot in col_node.get_children():
				for marker in row_slot.get_children():
					marker.queue_free()
