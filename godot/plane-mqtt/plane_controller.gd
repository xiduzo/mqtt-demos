## PlaneController
## Builds a low-poly plane and a scrolling world, then flies the plane from
## MQTT rotation messages (device motion sensor: x=pitch, y=roll, z=yaw degrees).
class_name PlaneController
extends Node3D

## Path to the chase Camera3D
@export var camera_path: NodePath
## How quickly the plane eases toward the target attitude (higher = snappier)
@export var smooth_speed: float = 6.0
## Forward scroll speed of the world (metres/second feel)
@export var scroll_speed: float = 18.0

var _plane: Node3D
var _ground: MeshInstance3D
var _ground_mat: StandardMaterial3D
var _markers: Array[MeshInstance3D] = []
var _camera: Camera3D

# Target attitude in degrees (set from MQTT), and the smoothed current value
var _target := Vector3.ZERO
var _current := Vector3.ZERO


func _ready() -> void:
	if camera_path:
		_camera = get_node_or_null(camera_path)
	_build_world()
	_build_plane()


## Builds the scrolling ground plane and floating reference markers.
func _build_world() -> void:
	_ground = MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(400, 400)
	_ground.mesh = plane_mesh
	_ground.position = Vector3(0, -12, 0)

	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_color = Color(0.42, 0.69, 0.30)
	_ground_mat.albedo_texture = _make_grid_texture()
	_ground_mat.uv1_scale = Vector3(60, 60, 1)
	_ground_mat.texture_repeat = true
	_ground.material_override = _ground_mat
	add_child(_ground)

	# Floating white pillars give a sense of speed and motion.
	var pillar := BoxMesh.new()
	pillar.size = Vector3(2, 16, 2)
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.95, 0.95, 0.97)
	for i in range(40):
		var m := MeshInstance3D.new()
		m.mesh = pillar
		m.material_override = pillar_mat
		m.position = Vector3(
			randf_range(-120.0, 120.0),
			-4.0,
			-randf_range(0.0, 240.0)
		)
		add_child(m)
		_markers.append(m)


## Assembles the plane from primitive meshes. Nose points toward -Z (forward).
func _build_plane() -> void:
	_plane = Node3D.new()
	add_child(_plane)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.88, 0.11, 0.28)
	body_mat.metallic = 0.3
	body_mat.roughness = 0.5

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.97, 0.98, 0.99)
	accent_mat.roughness = 0.6

	# Fuselage (capsule lying along Z)
	var fuselage := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.8
	cap.height = 6.0
	fuselage.mesh = cap
	fuselage.material_override = body_mat
	fuselage.rotation_degrees = Vector3(90, 0, 0)
	_plane.add_child(fuselage)

	# Nose cone
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 1.6
	nose.mesh = cone
	nose.material_override = body_mat
	nose.rotation_degrees = Vector3(-90, 0, 0)
	nose.position = Vector3(0, 0, -3.2)
	_plane.add_child(nose)

	# Main wing (spans X)
	var wing := MeshInstance3D.new()
	var wing_box := BoxMesh.new()
	wing_box.size = Vector3(9, 0.2, 1.6)
	wing.mesh = wing_box
	wing.material_override = accent_mat
	_plane.add_child(wing)

	# Tail wing
	var tail := MeshInstance3D.new()
	var tail_box := BoxMesh.new()
	tail_box.size = Vector3(3.4, 0.18, 1.0)
	tail.mesh = tail_box
	tail.material_override = accent_mat
	tail.position = Vector3(0, 0, 2.8)
	_plane.add_child(tail)

	# Vertical fin
	var fin := MeshInstance3D.new()
	var fin_box := BoxMesh.new()
	fin_box.size = Vector3(0.18, 1.6, 1.0)
	fin.mesh = fin_box
	fin.material_override = body_mat
	fin.position = Vector3(0, 0.8, 2.8)
	_plane.add_child(fin)


func _process(delta: float) -> void:
	var t := clampf(smooth_speed * delta, 0.0, 1.0)
	_current = _current.lerp(_target, t)

	if _plane:
		# x=pitch about X, z=yaw about Y, y=roll (banked) about -Z
		_plane.rotation_degrees = Vector3(_current.x, _current.z, -_current.y)

	# Scroll the world to fake constant forward flight; bank nudges drift.
	if _ground_mat:
		_ground_mat.uv1_offset.y -= scroll_speed * 0.002 * delta * 60.0

	var drift := _current.y * 0.02
	for m in _markers:
		m.position.z += scroll_speed * delta
		m.position.x -= drift
		if m.position.z > 30.0:
			m.position.z = -240.0
			m.position.x = randf_range(-120.0, 120.0)

	# Chase camera frames the plane dead-center.
	if _camera:
		_camera.position = Vector3(0, 3, 20)
		_camera.look_at(Vector3(0, 0, 0), Vector3.UP)


## Applies rotation data from the MQTTClient.rotation_received signal.
## rotation_data: { x: pitch, y: roll, z: yaw } in degrees.
func apply_rotation(rotation_data: Dictionary) -> void:
	if not rotation_data.get("valid", true):
		return
	_target = Vector3(
		float(rotation_data.get("x", 0.0)),
		float(rotation_data.get("y", 0.0)),
		float(rotation_data.get("z", 0.0))
	)


## Generates a simple grid texture (green cell with a light border).
func _make_grid_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fill := Color(0.42, 0.69, 0.30)
	var line := Color(1, 1, 1, 0.25)
	img.fill(fill)
	for i in range(size):
		img.set_pixel(i, 0, line)
		img.set_pixel(i, 1, line)
		img.set_pixel(0, i, line)
		img.set_pixel(1, i, line)
	return ImageTexture.create_from_image(img)
