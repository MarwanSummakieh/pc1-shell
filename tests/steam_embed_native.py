#!/usr/bin/env python3
"""Disposable X11 client: parenting, confinement, detachment and host failure."""
import importlib.util
import os
from pathlib import Path
import tempfile
from Xlib import X, display

spec = importlib.util.spec_from_file_location('steam_embed', Path(__file__).resolve().parents[1] /
    'os/files/usr/lib/marwanos/steam_embed.py')
embed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(embed)
client = display.Display()
root = client.screen().root
window = root.create_window(10, 10, 800, 600, 0, client.screen().root_depth,
                           X.InputOutput, X.CopyFromParent, background_pixel=0x204050)
window.map()
client.sync()
with tempfile.TemporaryDirectory() as directory:
    host = embed.Host(Path(directory), os.getpid())
    host.rect = [120, 90, 960, 540]
    host.attach(host.connection.create_resource_object('window', window.id))
    assert window.query_tree().parent.id == host.host.id
    host.tick({'rect': host.rect, 'visible': True, 'focus': True, 'action_id': '1', 'action': 'focus'})
    assert window.get_geometry().width == 960
    assert window.get_geometry().height == 540
    child = window.create_window(0, 0, 40, 40, 0, client.screen().root_depth)
    child.map()
    client.sync()
    assert host.contains_focus(host.connection.create_resource_object('window', child.id))
    assert not host.contains_focus(host.root)
    print('PASS: native child focus belongs to Steam; root focus does not')
    print('PASS: native client is a child of the pane at the requested size')
    shell = root.create_window(0, 0, 200, 200, 0, client.screen().root_depth)
    shell.destroy()
    client.sync()
    assert window.query_tree().parent.id == host.host.id
    print('PASS: unrelated shell window replacement preserves native client')
    host.detach()
    assert window.query_tree().parent.id == root.id
    assert window.get_geometry().width == 800
    print('PASS: orderly detach restores parent and original dimensions')
    host.is_steam = lambda candidate: candidate.id == window.id
    assert host.discover().id == window.id
    print('PASS: withdrawn Steam is rediscovered outside the WM client list')
    host.attach(host.connection.create_resource_object('window', window.id))
    host.connection.close()  # X-server save-set cleanup, without detach.
    client.sync()
    assert window.query_tree().parent.id == root.id
    print('PASS: host connection failure preserves and reparents the foreign client')
window.destroy()
client.close()
