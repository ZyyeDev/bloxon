extends Control

@export var serverListContainter : VBoxContainer

@export var nameLabel:Label
@export var selfPfp:Sprite2D

@export var homePage :Panel
@export var avatarPage :Panel
@export var configPage :Panel
@export var profilePage :Panel
@export var friendsPage :Panel
@export var FriendInfo :Panel

@export var friendContainterSmall:GridContainer
@export var friendsContainer:GridContainer

@export var homePageButton :Button
@export var profilePageButton :Button
@export var configPageButton :Button

var friends = []
var currentProfileID = 0
var isFriend = false

var friendServerId = ""

func _ready() -> void:
	_on_home_page_button_pressed()
	nameLabel.text = Global.username
	Client.serverlist_update.connect(_on_serverlist_update)
	Global.getAllServers()
	selfPfp.texture = await Client.getPlayerPfpTexture(Global.user_id,Global.token)
	updateSmallFriends()

func updateSmallFriends():
	for i in friendContainterSmall.get_children():
		i.queue_free()
	
	await getFriends()
	
	for i in friendsContainer.get_children():
		i.queue_free()
	
	var fi = 1
	
	var fData = {}
	for i in friends:
		var dat = await Client.getPlayerDataById(i,Global.token)
		fData[i] = dat.get("data",{})
		fi+= 1
		if fi > 6: break
	for i in fData:
		var data = fData[i]
		var button = load("res://scenes/menus/friend.tscn").instantiate()
		button.uName = data.get("username","ERROR_GETTING_USERNAME")
		button.uId = i
		button.serverId = data.get("serverId","")
		button.isOnline = data.get("serverId",null)!=null and data.get("serverId","")!=""
		if data.get("serverId",null) != null:
			button.serverId = data.get("serverId",null)
		button.pressed.connect(func():
			currentProfileID = i
			friendServerId = data.get("serverId","")
			showFriendInfo()
			)
		friendContainterSmall.add_child(button)

func _on_join_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/mainGame.tscn")
	Client.requestServer()

func _on_serverlist_update():
	var serverList = Client.servers
	for i in serverListContainter.get_children():
		i.queue_free()
	for i in serverList:
		var server = load("res://scenes/menus/normal_server.tscn").instantiate()
		server.plrs = i["players"]
		server.maxPlrs = i["max_players"]
		server.ping = i["ping"]
		server.ip = i["ip"]
		server.port = i["port"]
		serverListContainter.add_child(server)

func _on_update_servers_timeout() -> void:
	Global.getAllServers()

func hideAllPages():
	homePage.visible = false
	configPage.visible = false
	avatarPage.visible = false
	profilePage.visible = false
	friendsPage.visible = false
	
	homePageButton.modulate = Color8(179,179,179,255)
	configPageButton.modulate = Color8(179,179,179,255)

func _on_home_page_button_pressed() -> void:
	hideAllPages()
	homePage.visible = true
	homePageButton.modulate = Color8(0,188,250,255)

func _on_config_page_button_pressed() -> void:
	hideAllPages()
	configPage.visible = true
	configPageButton.modulate = Color8(0,188,250,255)

func _on_avatar_page_button_pressed() -> void:
	hideAllPages()
	avatarPage.visible = true

func _on_profile_page_button_pressed() -> void:
	hideAllPages()
	profilePage.visible = true
	var pData = await Client.getPlayerDataById(currentProfileID,Global.token)
	pData = pData.get("data",{})
	
	#HACK: fucking shit keep making all ints into floats, just keep it like that
	isFriend = pData.get("friends",{}).has(float(Global.user_id)) 
	var addfriendBtnText = "Add Friend"
	if isFriend:
		addfriendBtnText = "Remove Friend"
	
	$Control/ProfilePage/HBoxContainer/AddFriend.text = addfriendBtnText
	
	$Control/ProfilePage/HBoxContainer/PlayerName.text = pData.get("username","{ERROR_GETTING_USERNAME}")
	$Control/ProfilePage/HBoxContainer/Panel/Sprite2D2.texture = await Client.getPlayerPfpTexture(currentProfileID,Global.token)

func getFriends():
	var response = await Client.getFriendsList(Global.user_id,Global.token)
	friends = response.get("data",[])

func _on_see_all_friends_pressed() -> void:
	await getFriends()
	hideAllPages()
	friendsPage.visible = true
	friendsContainer.visible = true
	$Control/FriendsPage/Control.visible = false
	$Control/FriendsPage/FriendList.visible = true
	$Control/FriendsPage/FriendRequests.visible = true
	for i in friendsContainer.get_children():
		i.queue_free()
	var fData = {}
	for i in friends:
		var dat = await Client.getPlayerDataById(i,Global.token)
		fData[i] = dat.get("data",{})
	if fData.size() <= 0:
		var label = Label.new()
		label.text = "  No friends :("
		label.add_theme_color_override("font_color",Color8(188,188,188,255))
		friendsContainer.add_child(label)
	for i in fData:
		var data = fData[i]
		var button = load("res://scenes/menus/friend.tscn").instantiate()
		button.uName = data.get("username","{ERROR_GETTIG_USERNAME}")
		button.uId = i
		button.isOnline = data.get("serverId",null)!=null and data.get("serverId","")!=""
		button.pressed.connect(func():
			currentProfileID = i
			_on_profile_page_button_pressed()
			)
		friendsContainer.add_child(button)

func _on_back_friend_list_pressed() -> void:
	friendsContainer.visible = true
	$Control/FriendsPage/Control.visible = false

func _on_line_edit_text_submitted(new_text: String) -> void:
	var searchedPlayers = await Client.searchUsers(new_text,20)
	if !searchedPlayers:return
	searchedPlayers = searchedPlayers["users"]
	friendsContainer.visible = false
	$Control/FriendsPage/Control.visible = true
	$Control/FriendsPage/FriendList.visible = false
	$Control/FriendsPage/FriendRequests.visible = false
	
	for i in $Control/FriendsPage/Control/GridContainer.get_children():
		i.queue_free()
	var fData = {}
	for i in searchedPlayers:
		var response = await Client.getPlayerDataById(int(i.user_id),Global.token)
		fData[i.user_id] = response.get("data",{})
		
	if fData.size() <= 0:
		var label = Label.new()
		label.text = "  No users found."
		label.add_theme_color_override("font_color",Color8(188,188,188,255))
		$Control/FriendsPage/Control/GridContainer.add_child(label)
	for i in fData:
		var data = fData[i]
		var button = load("res://scenes/menus/friend.tscn").instantiate()
		button.uName = data["username"]
		button.uId = i
		button.isOnline = false
		button.pressed.connect(func():
			currentProfileID = i
			_on_profile_page_button_pressed()
			)
		$Control/FriendsPage/Control/GridContainer.add_child(button)

func _on_add_friend_pressed() -> void:
	if currentProfileID == 0: return
	if isFriend:
		isFriend = false
		$Control/ProfilePage/HBoxContainer/AddFriend.text = "Add Friend"
		await Client.removeFriend(Global.user_id,currentProfileID,Global.token)
	else:
		var response = await Client.sendFriendRequest(Global.user_id,currentProfileID,Global.token)

func _on_friend_list_pressed() -> void:
	_on_see_all_friends_pressed()
	$Control/FriendsPage/GridContainer.visible = true
	$Control/FriendsPage/FriendRequestList.visible = false

func _on_friend_requests_pressed() -> void:
	$Control/FriendsPage/GridContainer.visible = false
	$Control/FriendsPage/FriendRequestList.visible = true
	await Global.wait(.5)
	var friendRequests = await Client.getFriendRequests(Global.user_id,Global.token)
	for i in $Control/FriendsPage/FriendRequestList.get_children():
		i.queue_free()
	if not friendRequests.get("success",false): return
	friendRequests = friendRequests.get("data",{}).get("incoming",{})
	var fData = {}
	for i in friendRequests:
		var dat = await Client.getPlayerDataById(i,Global.token)
		fData[i] = dat.get("data",{})
	if fData.size() <= 0:
		var label = Label.new()
		label.text = "  No friend requests"
		label.add_theme_color_override("font_color",Color8(188,188,188,255))
		$Control/FriendsPage/FriendRequestList.add_child(label)
	for i in fData:
		var data = fData[i] 
		var button = load("res://scenes/menus/friend.tscn").instantiate()
		button.uName = data.get("username","{ERROR_GETTIG_USERNAME}")
		button.uId = i
		button.isOnline = data.get("serverId",null)!=null and data.get("serverId","")!=""
		button.pressed.connect(func():
			Client.acceptFriendRequest(Global.user_id,i,Global.token)
			)
		$Control/FriendsPage/FriendRequestList.add_child(button)

func _on_log_out_pressed() -> void:
	Global.token = ""
	Global.saveLocal()
	
	get_tree().change_scene_to_file("res://scenes/INIT.tscn")

func showFriendInfo():
	$Control/FriendInfo/AnimationPlayer.play("show")
	FriendInfo.visible = true
	
	$"Control/FriendInfo/bg/_VBoxContainer_33/Join Friend".visible = friendServerId != "" and friendServerId != null
	$"Control/FriendInfo/bg/_VBoxContainer_33/_HSeparator_20".visible = friendServerId != "" and friendServerId != null

func hideFriendInfo():
	$Control/FriendInfo/AnimationPlayer.play("hide")
	await Global.wait(.5)
	FriendInfo.visible = false

func _on_join_friend_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/mainGame.tscn")
	if friendServerId != "":
		Client.connectToServerID(friendServerId)

func _on_view_friend_profile_pressed() -> void:
	FriendInfo.visible = false
	_on_profile_page_button_pressed()
