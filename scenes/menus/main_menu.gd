extends Control

@export var serverListContainter : VBoxContainer

@export var nameLabel:Label
@export var currencyLabel:Label
@export var selfPfp:Sprite2D

@export var homePage :Panel
@export var avatarPage :Panel
@export var configPage :Panel
@export var profilePage :Panel
@export var friendsPage :Panel
@export var FriendInfo :Panel
@export var ItemPage :Panel

@export var friendContainterSmall:GridContainer
@export var friendsContainer:GridContainer

@export var marketplaceContainer:GridContainer
@export var inventoryContainer:GridContainer

@export var homePageButton :Button
@export var profilePageButton :Button
@export var configPageButton :Button

@export var avatarLoadingSpinner:Sprite2D
@export var itemNameLabel:Label
@export var itemCostLabel:Label
@export var itemIcon:Sprite2D

@export var buyAccessoryButton:Button
@export var avatarPages:Control
@export var avatarEditorTab:Control
@export var avatarTabs:HBoxContainer
@export var avatarColorsPage:Control
@export var avatarColorPicker:ColorPicker

var currentPage = "home"

var currentAccessoryId = 0

var currentLimbEditing = ""
var newAvatarColor = {}

var friends = []
var currentProfileID = 0
var isFriend = false

var currentAccessories = []
var invUpdateFuncs = []

var friendServerId = ""

func _ready() -> void:
	_on_home_page_button_pressed()
	nameLabel.text = Global.username
	Client.serverlist_update.connect(_on_serverlist_update)
	Global.getAllServers()
	selfPfp.texture = await Client.getPlayerPfpTexture(Global.user_id,Global.token)
	updateSmallFriends()
	updateCurrency()
	for i:Button in avatarColorsPage.get_node("Control").get_children():
		i.pressed.connect(func():
			currentLimbEditing = i.name
			avatarColorPicker.color = Global.avatarData["bodyColors"][currentLimbEditing.to_lower().replace(" ","_")]
			)

func _process(delta: float) -> void:
	if currentLimbEditing != "":
		avatarColorPicker.visible = true
	else:
		avatarColorPicker.visible = false
	
	for i:Callable in invUpdateFuncs:
		i.call()

func updateCurrency():
	var currency = await Client.getCurrency(Global.user_id,Global.token)
	currencyLabel.text = "𝔹 " + str(Client.format_number(currency))

func updateSmallFriends():
	for i in friendContainterSmall.get_children():
		if i.is_in_group("addFriends"):
			continue
		i.queue_free()
	
	await getFriends()
	
	for i in friendsContainer.get_children():
		if i.is_in_group("addFriends"):
			continue
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
	playSound(load("res://assets/sounds/UI/ButtonPress.wav"),-10)
	await CoreGui.showConnect("Loading game...")
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
	ItemPage.visible = false
	
	homePageButton.modulate = Color8(179,179,179,255)
	configPageButton.modulate = Color8(179,179,179,255)

func playSound(loaded,volume=0):
	var snd = AudioStreamPlayer.new()
	Global.add_child(snd)
	snd.volume_db = volume
	snd.stream = loaded
	snd.play()
	Debris.addItem(snd,snd.stream.get_length())

func playScreenChange():
	playSound(load("res://assets/sounds/UI/ScreenChange.wav"))

func _on_home_page_button_pressed() -> void:
	if currentPage != "home":
		playScreenChange()
	currentPage = "home"
	hideAllPages()
	homePage.visible = true
	homePageButton.modulate = Color8(0,188,250,255)

func _on_config_page_button_pressed() -> void:
	if currentPage != "config":
		playScreenChange()
	currentPage = "config"
	hideAllPages()
	configPage.visible = true
	configPageButton.modulate = Color8(0,188,250,255)

func _on_avatar_page_button_pressed() -> void:
	if currentPage != "avatar":
		playScreenChange()
	currentPage = "avatar"
	hideAllPages()
	avatarPage.visible = true
	updateInventory()

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
		if i.is_in_group("addFriends"):
			continue
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
	await Global.wait(.2)
	FriendInfo.visible = false

func _on_join_friend_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/mainGame.tscn")
	if friendServerId != "":
		Client.connectToServerID(friendServerId)

func _on_view_friend_profile_pressed() -> void:
	FriendInfo.visible = false
	_on_profile_page_button_pressed()

func requestMarket():
	return await Client.listMarketAccessories(Global.token,{},{
		"page": 1,
		"limit": 20
	})

func _on_addFriends_pressed() -> void:
	_on_see_all_friends_pressed()

func updateMarketplace():
	avatarLoadingSpinner.visible = true
	for i in marketplaceContainer.get_children():
		i.queue_free()
	Global.avatarData = await Client.getAvatar(Global.user_id,Global.token)
	var requestData = await requestMarket()
	avatarLoadingSpinner.visible = false
	print("requestData ",requestData)
	var marketData:Array = requestData.get("data",{}).get("items",[])
	print(marketData)
	if !marketData.is_empty():
		for myData in marketData:
			#print(" i is ",i)
			#var myData = marketData[i]
			print(myData)
			var id = int(myData["id"])
			var Name = myData["name"]
			var type = myData["type"]
			var price = myData["price"]
			var downloadUrl = myData["downloadUrl"]
			var iconUrl = myData["iconUrl"]
			var createdAt = myData["createdAt"]
			var equipSlot = myData["equipSlot"]
			
			Client.downloadAccessoryModel(downloadUrl,id)
			
			var shopInst = load("res://scenes/menus/shop_item.tscn").instantiate()
			shopInst.spriteTexture = await Client.loadTextureFromUrl(iconUrl)
			shopInst.itemName = Name
			shopInst.Cost = price
			shopInst.pressed.connect(func():showItemPage(myData))
			marketplaceContainer.add_child(shopInst)

func showItemPage(myData:Dictionary):
	hideAllPages()
	avatarLoadingSpinner.visible = true
	var successAc = await Client.getUserAccessories(Global.user_id,Global.token)
	avatarLoadingSpinner.visible = false
	ItemPage.visible = true
	var id = int(myData["id"])
	var Name = myData["name"]
	var type = myData["type"]
	var price = myData["price"]
	var downloadUrl = myData["downloadUrl"]
	var createdAt = myData["createdAt"]
	var iconUrl = myData["iconUrl"]
	var equipSlot = myData["equipSlot"]
	
	itemIcon.texture = await Client.loadTextureFromUrl(iconUrl)
	
	currentAccessoryId = id
	
	itemNameLabel.text = Name
	itemCostLabel.text = "𝔹 " + str(int(price))
	if checkOwnsAccessory(successAc,currentAccessoryId):
		buyAccessoryButton.text = "Owned"
	else:
		buyAccessoryButton.text = "Buy"

func checkOwnsAccessory(rawRequest:Dictionary,acId:int):
	var userAccessories = rawRequest.get("data",[])
	## server will return all of the values as ints, or godot is dumb and converts them into ints.
	## store here all values as int. Maybe there's a better way, but idgaf.
	var intAccessories = []
	for i in userAccessories:
		intAccessories.append(int(i))
	return acId in intAccessories

func _on_buy_item_button_pressed() -> void:
	var successAc = await Client.getUserAccessories(Global.user_id,Global.token)
	if checkOwnsAccessory(successAc,currentAccessoryId):
		return
	avatarLoadingSpinner.visible = true
	ItemPage.visible = false
	var success = await Client.buyAccessory(currentAccessoryId,Global.token)
	print(success)
	avatarLoadingSpinner.visible = false
	ItemPage.visible = true
	if success.get("success",false):
		playSound(load("res://assets/sounds/UI/PurchaseSuccess.wav"))
	else:
		playSound(load("res://assets/sounds/UI/PopUp2.wav"))

func showChangeAvatarColor():
	newAvatarColor = Global.avatarData.duplicate(true)
	avatarPages.visible = false
	avatarTabs.visible = false
	inventoryContainer.visible = false
	avatarColorsPage.visible = true

func _on_color_picker_color_changed(color: Color) -> void:
	newAvatarColor["bodyColors"][currentLimbEditing.to_lower().replace(" ","_")] = "#"+color.to_html(false)
	$Control/AvatarPage/SubViewport.changeColors(newAvatarColor)

func _on_apply_avatar_pressed() -> void:
	avatarColorsPage.visible = false
	avatarLoadingSpinner.visible = true
	Global.avatarData = newAvatarColor.duplicate(true)
	await Client.updateAvatar(Global.user_id,newAvatarColor,Global.token)
	avatarLoadingSpinner.visible = false
	avatarColorsPage.visible = false
	inventoryContainer.visible = true
	avatarPages.visible = true
	avatarTabs.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	selfPfp.texture = await Client.getPlayerPfpTexture(Global.user_id,Global.token)

func _on_cancel_avatar_pressed() -> void:
	avatarColorsPage.visible = false
	avatarLoadingSpinner.visible = false
	avatarColorsPage.visible = false
	inventoryContainer.visible = true
	avatarPages.visible = true
	avatarTabs.visible = true

func _on_avatar_colors_pressed() -> void:
	showChangeAvatarColor()

func _on_inventory_button_pressed() -> void:
	marketplaceContainer.visible = false
	avatarEditorTab.visible = true

func _on_marketplace_pressed() -> void:
	updateMarketplace()
	marketplaceContainer.visible = true
	avatarEditorTab.visible = false

func updateInventory():
	Global.avatarData = await Client.getAvatar(Global.user_id,Global.token)
	await getAvatar(false)
	avatarLoadingSpinner.visible = true
	invUpdateFuncs.clear()
	for i in inventoryContainer.get_children():
		i.queue_free()
	var req = await Client.getUserAccessories(Global.user_id,Global.token)
	avatarLoadingSpinner.visible = false
	var data = req.get("data",[])
	print("datadata ",req)
	
	for i in data:
		var acReq = await Client.getAccessoryData(int(i),Global.token)
		var myData = acReq.get("data",{})
		if myData.is_empty(): continue
		var id = int(myData["id"])
		var Name = myData["name"]
		var type = myData["type"]
		var price = myData["price"]
		var downloadUrl = myData["downloadUrl"]
		var iconUrl = myData["iconUrl"]
		var createdAt = myData["createdAt"]
		var equipSlot = myData["equipSlot"]
		
		var shopInst = load("res://scenes/menus/shop_item.tscn").instantiate()
		shopInst.spriteTexture = await Client.loadTextureFromUrl(iconUrl)
		
		invUpdateFuncs.append(func():
			if Global.avatarData["accessories"].has(id):
				shopInst.light()
			else:
				shopInst.normal()
			)
		
		shopInst.itemName = Name
		shopInst.Cost = price
		shopInst.pressed.connect(func():
			var newData:Dictionary = Global.avatarData.duplicate(true)
			var didEquip = false
			if newData["accessories"].has(float(id)):
				newData["accessories"].erase(float(id))
			else:
				didEquip = true
				newData["accessories"].append(float(id))
			print(newData)
			Global.avatarData = newData.duplicate(true)
			Client.updateAvatar(Global.user_id,Global.avatarData,Global.token)
			for v in currentAccessories:
				if is_instance_valid(v):
					v.queue_free()
			currentAccessories.clear()
			if didEquip:
				var accMesh = await Client.addAccessoryToPlayer(id,$Control/AvatarPage/SubViewport/Node3D)
				if accMesh:
					currentAccessories.append(accMesh)
			)
		inventoryContainer.add_child(shopInst)

func createCurrencyPackages():
	var packages = await Client.getCurrencyPackages()
	# TODO

func getAvatar(getAvatarFromServer:bool):
	if getAvatarFromServer:
		Global.avatarData = await Client.getAvatar(Global.user_id,Global.token)
	for v in currentAccessories:
		if is_instance_valid(v):
			v.queue_free()
	currentAccessories.clear()
	for id in Global.avatarData["accessories"]:
		var accMesh = await Client.addAccessoryToPlayer(id,$Control/AvatarPage/SubViewport/Node3D)
		if accMesh:
			currentAccessories.append(accMesh)
