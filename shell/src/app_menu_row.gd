extends "res://src/settings_row.gd"

## One item in the running-application menu.
##
## It extends the settings row for store_tab.gd's reason: tabs, rows, cards and
## now menu items stay one family of focusable rectangles, and the only things
## an item adds are an id and a press that means something. _on_pressed is
## overridden rather than re-connected -- the base class connected its own
## method name to `pressed`, and GDScript resolves that call on the instance,
## so the override is the whole mechanism.
##
## The id rather than the label is what the menu switches on. The label is what
## a person reads and will be reworded; the id is what the code matches, and
## the two should not be the same string.

signal chosen(id: String)

var id: String = ""


func setup_item(item_id: String, label_text: String, icon_name: String) -> void:
	id = item_id
	setup(label_text, "", icon_name)


func _on_pressed() -> void:
	chosen.emit(id)
