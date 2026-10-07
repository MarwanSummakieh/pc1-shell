extends "res://src/achievement_toast.gd"

## Loaded after autoload initialization, observing the real pre-tag native XID.
var classification_calls: Array = []
var before_classification: Callable


func _set_external_overlay(enabled: bool) -> bool:
	classification_calls.append(enabled)
	if before_classification.is_valid():
		before_classification.call()
	print("Toast fixture: setting external classification")
	var result := super._set_external_overlay(enabled)
	print("Toast fixture: external classification verified=", result)
	return result
