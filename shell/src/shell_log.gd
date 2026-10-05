extends Node

## Logging, aimed at the journal rather than at a screen.
##
## The appliance shows no text by design (D6), so `journalctl -b -t marwanos-session` is
## the only place a shell failure can be read. marwanos-session re-execs itself
## through `systemd-cat --level-prefix=true` and the client inherits those
## descriptors, which means systemd parses a leading `<N>` on each line as a
## syslog priority: `<3>` err, `<4>` warning, `<6>` info. Emitting the prefixes
## here is what makes `journalctl -p err -t marwanos-session` surface a shell problem
## instead of burying it under engine chatter, and it puts the shell's lines in
## the same shape as the session script's.
##
## In the Godot editor the prefixes are visible noise in the Output panel. That is
## the correct trade: the desk has a console and the appliance does not.
##
## Everything goes through print() rather than printerr(). stdout and stderr are
## separate pipes into the same journal stream, and interleaving them reorders
## lines relative to each other -- which is exactly what you need to be able to
## trust when reading a crash backwards.

const TAG := "marwanos-shell"


func info(message: String) -> void:
	print("<6>", TAG, ": ", message)


func warn(message: String) -> void:
	print("<4>", TAG, ": ", message)


func error(message: String) -> void:
	print("<3>", TAG, ": ", message)
