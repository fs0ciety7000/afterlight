class_name TestCase
extends RefCounted
## Base class for unit tests: records failures instead of aborting.

var failures: PackedStringArray = []


func assert_eq(actual: Variant, expected: Variant, label: String = "") -> void:
	if actual != expected:
		failures.append("%s expected %s, got %s" % [label, expected, actual])


func assert_true(value: bool, label: String = "") -> void:
	if not value:
		failures.append("%s expected true" % label)


func assert_near(
	actual: float, expected: float, epsilon: float = 0.0001, label: String = ""
) -> void:
	if absf(actual - expected) > epsilon:
		failures.append("%s expected %f ± %f, got %f" % [label, expected, epsilon, actual])
