## RotationController
## Manages rotation state and applies transformations to the cube.
## Parses MQTT rotation messages and validates rotation values.
## Also handles cube configuration (size, color, material properties).
## Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.4, 5.3, 5.4
class_name RotationController
extends Node

enum RotationMode { ABSOLUTE, RELATIVE }

## Path to the cube MeshInstance3D node
@export var cube_path: NodePath
## Rotation mode: ABSOLUTE sets rotation directly, RELATIVE adds to current
@export var rotation_mode: RotationMode = RotationMode.RELATIVE
## Whether to smoothly interpolate rotation changes
@export var smooth_rotation: bool = true
## Speed of smooth rotation interpolation
@export var rotation_speed: float = 5.0

## Cube configuration options
## Requirements: 5.3, 5.4
@export_group("Cube Configuration")
## Size of the cube (all components must be > 0)
@export var cube_size: Vector3 = Vector3(2, 2, 2)
## Color of the cube material
@export var cube_color: Color = Color(0.2, 0.6, 0.9)
## Metallic property of the cube material (0.0 to 1.0)
@export_range(0.0, 1.0) var cube_metallic: float = 0.3
## Roughness property of the cube material (0.0 to 1.0)
@export_range(0.0, 1.0) var cube_roughness: float = 0.7

## Default values for cube configuration
const DEFAULT_CUBE_SIZE := Vector3(2, 2, 2)
const DEFAULT_CUBE_COLOR := Color(0.2, 0.6, 0.9)
const DEFAULT_CUBE_METALLIC := 0.3
const DEFAULT_CUBE_ROUGHNESS := 0.7

var _cube: MeshInstance3D
var _target_rotation: Vector3 = Vector3.ZERO


func _ready() -> void:
	if cube_path:
		_cube = get_node_or_null(cube_path)
	
	# Apply cube configuration after getting the cube reference
	_apply_cube_configuration()


func _process(delta: float) -> void:
	if not _cube:
		return
	
	if smooth_rotation:
		# Smoothly interpolate toward target rotation
		_cube.rotation_degrees.x = lerp(_cube.rotation_degrees.x, _target_rotation.x, rotation_speed * delta)
		_cube.rotation_degrees.y = lerp(_cube.rotation_degrees.y, _target_rotation.y, rotation_speed * delta)
		_cube.rotation_degrees.z = lerp(_cube.rotation_degrees.z, _target_rotation.z, rotation_speed * delta)
	else:
		# Set rotation directly without interpolation
		_cube.rotation_degrees = _target_rotation


## Parses a JSON rotation message payload and returns a rotation data dictionary.
## Returns {valid: false} for invalid JSON.
## Missing fields default to zero.
## Requirements: 3.1, 3.2, 3.3, 3.4
func _parse_rotation_message(payload: String) -> Dictionary:
	var result: Dictionary = {
		"x": 0.0,
		"y": 0.0,
		"z": 0.0,
		"mode": "absolute",
		"valid": true
	}
	
	# Attempt to parse JSON
	var json := JSON.new()
	var parse_error := json.parse(payload)
	
	if parse_error != OK:
		push_warning("[RotationController] Invalid JSON in rotation message: " + payload.substr(0, 50))
		return {"valid": false}
	
	var data = json.get_data()
	
	# Ensure we got a dictionary
	if not data is Dictionary:
		push_warning("[RotationController] Rotation message is not a JSON object")
		return {"valid": false}
	
	# Extract and validate rotation values, using zero for missing/invalid fields
	result["x"] = _validate_rotation_value(data.get("x", 0.0))
	result["y"] = _validate_rotation_value(data.get("y", 0.0))
	result["z"] = _validate_rotation_value(data.get("z", 0.0))
	
	# Extract mode if present
	if data.has("mode") and data["mode"] is String:
		result["mode"] = data["mode"]
	
	return result


## Validates that a rotation value is numeric and returns it as a float.
## Returns 0.0 for non-numeric values.
## Requirements: 3.5
func _validate_rotation_value(value: Variant) -> float:
	if value is float:
		return value
	elif value is int:
		return float(value)
	else:
		if value != null:
			push_warning("[RotationController] Non-numeric rotation value: " + str(value))
		return 0.0


## Clamps a rotation value to the valid range [-360, 360] using modulo arithmetic.
## Requirements: 4.4
func _clamp_rotation(degrees: float) -> float:
	# Use fmod to normalize the value
	var clamped := fmod(degrees, 360.0)
	return clamped


## Applies rotation data to the cube.
## Handles absolute rotation from Device Motion sensor (values in degrees).
## Requirements: 4.1, 4.2, 4.3, 4.5
func apply_rotation(rotation_data: Dictionary) -> void:
	# Ignore invalid rotation data
	if not rotation_data.get("valid", true):
		return
	
	if not _cube:
		return
	
	# Extract rotation values (already in degrees from Device Motion)
	var x := float(rotation_data.get("x", 0.0))
	var y := float(rotation_data.get("y", 0.0))
	var z := float(rotation_data.get("z", 0.0))
	
	# Set target rotation directly (absolute mode)
	_target_rotation = Vector3(x, y, z)


## Sets the rotation mode at runtime.
## Requirements: 5.2
func set_rotation_mode(mode: RotationMode) -> void:
	rotation_mode = mode


## Validates cube size - all components must be > 0.
## Returns the validated size or default if invalid.
## Requirements: 5.4
func _validate_cube_size(size: Vector3) -> Vector3:
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		push_warning("[RotationController] Invalid cube size: " + str(size) + ". All components must be > 0. Using default: " + str(DEFAULT_CUBE_SIZE))
		return DEFAULT_CUBE_SIZE
	return size


## Validates color - must be a valid Color.
## Returns the validated color or default if invalid.
## Requirements: 5.4
func _validate_color(color: Color) -> Color:
	# Color in Godot is always valid as a type, but we check for reasonable values
	# RGBA components should be in [0, 1] range for standard colors
	# However, HDR colors can exceed 1.0, so we only check for negative values
	if color.r < 0 or color.g < 0 or color.b < 0 or color.a < 0:
		push_warning("[RotationController] Invalid cube color: " + str(color) + ". Color components cannot be negative. Using default: " + str(DEFAULT_CUBE_COLOR))
		return DEFAULT_CUBE_COLOR
	return color


## Validates metallic value - must be in range [0.0, 1.0].
## Returns the validated value or default if invalid.
## Requirements: 5.4
func _validate_metallic(value: float) -> float:
	if value < 0.0 or value > 1.0:
		push_warning("[RotationController] Invalid metallic value: " + str(value) + ". Must be in range [0.0, 1.0]. Using default: " + str(DEFAULT_CUBE_METALLIC))
		return DEFAULT_CUBE_METALLIC
	return value


## Validates roughness value - must be in range [0.0, 1.0].
## Returns the validated value or default if invalid.
## Requirements: 5.4
func _validate_roughness(value: float) -> float:
	if value < 0.0 or value > 1.0:
		push_warning("[RotationController] Invalid roughness value: " + str(value) + ". Must be in range [0.0, 1.0]. Using default: " + str(DEFAULT_CUBE_ROUGHNESS))
		return DEFAULT_CUBE_ROUGHNESS
	return value


## Applies cube configuration (size, color, material properties) to the cube.
## Validates all configuration values and uses defaults for invalid values.
## Requirements: 5.3, 5.4
func _apply_cube_configuration() -> void:
	if not _cube:
		return
	
	# Validate all configuration values
	var validated_size := _validate_cube_size(cube_size)
	var validated_color := _validate_color(cube_color)
	var validated_metallic := _validate_metallic(cube_metallic)
	var validated_roughness := _validate_roughness(cube_roughness)
	
	# Apply cube size to the BoxMesh
	if _cube.mesh and _cube.mesh is BoxMesh:
		var box_mesh: BoxMesh = _cube.mesh as BoxMesh
		box_mesh.size = validated_size
	else:
		# Create a new BoxMesh if one doesn't exist
		var box_mesh := BoxMesh.new()
		box_mesh.size = validated_size
		_cube.mesh = box_mesh
	
	# Apply color and material properties to the StandardMaterial3D
	var material: StandardMaterial3D
	if _cube.material_override and _cube.material_override is StandardMaterial3D:
		material = _cube.material_override as StandardMaterial3D
	else:
		# Create a new StandardMaterial3D if one doesn't exist
		material = StandardMaterial3D.new()
		_cube.material_override = material
	
	material.albedo_color = validated_color
	material.metallic = validated_metallic
	material.roughness = validated_roughness
