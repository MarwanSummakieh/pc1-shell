extends "res://src/settings_row.gd"

## A settings row that DOES something.
##
## settings_row.gd's base behaviour is to log "read-only in Phase 0" on A --
## which was the honest thing to say when no row did anything, and is now
## exactly wrong for the rows that do. Overriding `_on_pressed` replaces that
## log rather than adding to it: the base class connected the signal to its own
## method NAME, and GDScript resolves that on the instance, so the override is
## the whole mechanism. Same trick as store_tab.gd.
##
## Emitting rather than acting keeps the row ignorant of what it opens, so the
## Wi-Fi row in settings and a network row on the Wi-Fi screen can be the same
## kind of object with different consequences.

signal activated()


func _on_pressed() -> void:
	activated.emit()
