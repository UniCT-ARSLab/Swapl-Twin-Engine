class_name PIDController
extends RefCounted

var kp: float
var ki: float
var kd: float
var max_value: float

var integral: float = 0.0
var last_error: float = 0.0

func _init(_kp: float, _ki: float, _kd: float, _max_value: float):
	kp = _kp
	ki = _ki
	kd = _kd
	max_value = _max_value

func evaluate(delta_t: float, error: float) -> float:
	# Proportional term
	var p = kp * error
	
	# Integral term
	integral += error * delta_t
	var i = ki * integral
	
	# Derivative term
	var derivative = 0.0
	if delta_t > 0:
		derivative = (error - last_error) / delta_t
	var d = kd * derivative
	
	last_error = error
	
	# Calculate output
	var output = p + i + d
	
	# Clamp output
	output = clamp(output, -max_value, max_value)
	
	return output

func reset():
	integral = 0.0
	last_error = 0.0
