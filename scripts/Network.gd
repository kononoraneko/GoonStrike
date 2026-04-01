extends Node

var peer : ENetMultiplayerPeer

func host():
	peer = ENetMultiplayerPeer.new()
	peer.create_server(7777)
	multiplayer.multiplayer_peer = peer
	print("Hosting")

func join(ip):
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, 7777)
	multiplayer.multiplayer_peer = peer
	print("Joining")

func is_server():
	return multiplayer.is_server()
