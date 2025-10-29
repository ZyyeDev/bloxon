extends Node

var payment_plugin = null
var pending_purchases = []
var purchase_in_progress = false

signal purchase_success(product_id, currency_awarded)
signal purchase_failed(error_message)
signal ad_reward_success(reward_amount)
signal ad_reward_failed(error_message)

func _ready():
	if Engine.has_singleton("GodotGooglePlayBilling"):
		payment_plugin = Engine.get_singleton("GodotGooglePlayBilling")
		payment_plugin.connect("purchases_updated", _on_purchases_updated)
		payment_plugin.connect("purchase_error", _on_purchase_error)
		payment_plugin.connect("connected", _on_billing_connected)
		payment_plugin.startConnection()
	else:
		print("Google Play Billing not available")
	
	load_pending_purchases()

func _on_billing_connected():
	print("Connected to Google Play Billing")
	query_purchases()

func query_purchases():
	if payment_plugin:
		var result = payment_plugin.queryPurchases("inapp")
		if result.status == OK:
			for purchase in result.purchases:
				if not purchase.is_acknowledged:
					verify_purchase_with_server(purchase.product_id, purchase.purchase_token)

func get_available_products():
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var headers = ["Content-Type: application/json"]
	httpRequest.request(Global.masterIp + "/payments/packages", headers, HTTPClient.METHOD_GET, "")
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		if jsonResponse and jsonResponse.has("success") and jsonResponse.success:
			return jsonResponse.data.packages
	
	return []

func purchase_product(product_id: String):
	if purchase_in_progress:
		emit_signal("purchase_failed", "Another purchase is in progress")
		return
	
	if not payment_plugin:
		emit_signal("purchase_failed", "Payment system not available")
		return
	
	purchase_in_progress = true
	
	var purchase_params = {
		"productId": product_id,
		"productType": "inapp"
	}
	
	payment_plugin.purchase(purchase_params)

func _on_purchases_updated(purchases: Array):
	purchase_in_progress = false
	
	for purchase in purchases:
		if purchase.purchase_state == 1:
			await verify_purchase_with_server(purchase.product_id, purchase.purchase_token)

func _on_purchase_error(code: int, message: String):
	purchase_in_progress = false
	print("Purchase error: ", code, " - ", message)
	emit_signal("purchase_failed", message)

func verify_purchase_with_server(product_id: String, purchase_token: String):
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": Global.token,
		"product_id": product_id,
		"purchase_token": purchase_token
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/payments/purchase", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		
		if jsonResponse and jsonResponse.has("success"):
			if jsonResponse.success:
				var currency_awarded = jsonResponse.data.currency_awarded
				print("Purchase verified! Awarded: ", currency_awarded)
				emit_signal("purchase_success", product_id, currency_awarded)
				remove_pending_purchase(purchase_token)
			else:
				var error_code = jsonResponse.error.code
				if error_code == "ALREADY_PROCESSED":
					print("Purchase already processed")
					remove_pending_purchase(purchase_token)
				else:
					print("Purchase verification failed: ", jsonResponse.error.message)
					save_pending_purchase(product_id, purchase_token)
					emit_signal("purchase_failed", jsonResponse.error.message)
		else:
			save_pending_purchase(product_id, purchase_token)
			emit_signal("purchase_failed", "Invalid server response")
	else:
		save_pending_purchase(product_id, purchase_token)
		emit_signal("purchase_failed", "Server error")

func watch_ad_for_reward():
	var ad_network = "admob"
	var ad_unit_id = "ca-app-pub-3940256099942544/5224354917"
	var reward_amount = 10
	
	var verification_hash = generate_ad_verification(Global.user_id, ad_network, ad_unit_id, reward_amount)
	
	await show_rewarded_ad()
	
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": Global.token,
		"ad_network": ad_network,
		"ad_unit_id": ad_unit_id,
		"reward_amount": reward_amount,
		"verification_data": {
			"hash": verification_hash
		}
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/payments/ad_reward", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		
		if jsonResponse and jsonResponse.has("success") and jsonResponse.success:
			var reward = jsonResponse.data.reward_amount
			print("Ad reward claimed: ", reward)
			emit_signal("ad_reward_success", reward)
		else:
			var error_msg = jsonResponse.error.message if jsonResponse.has("error") else "Unknown error"
			emit_signal("ad_reward_failed", error_msg)
	else:
		emit_signal("ad_reward_failed", "Server error")

func show_rewarded_ad():
	if Engine.has_singleton("AdMob"):
		var admob = Engine.get_singleton("AdMob")
		admob.show_rewarded_video()
		
		var timeout = 60.0
		var elapsed = 0.0
		while elapsed < timeout:
			await get_tree().create_timer(0.5).timeout
			elapsed += 0.5
			
			if admob.is_rewarded_video_loaded():
				return
	else:
		print("AdMob not available, simulating ad watch")
		await get_tree().create_timer(2.0).timeout

func generate_ad_verification(user_id: int, ad_network: String, ad_unit_id: String, reward_amount: int) -> String:
	var data = str(user_id) + ad_network + ad_unit_id + str(reward_amount)
	return data.sha256_text()

func get_payment_history():
	var httpRequest = HTTPRequest.new()
	add_child(httpRequest)
	
	var requestData = {
		"token": Global.token
	}
	
	var headers = ["Content-Type: application/json"]
	var jsonString = JSON.stringify(requestData)
	
	httpRequest.request(Global.masterIp + "/payments/history", headers, HTTPClient.METHOD_POST, jsonString)
	
	var response = await httpRequest.request_completed
	httpRequest.queue_free()
	
	if response[1] == 200:
		var jsonResponse = JSON.parse_string(response[3].get_string_from_utf8())
		if jsonResponse and jsonResponse.has("success") and jsonResponse.success:
			return jsonResponse.data
	
	return []

func save_pending_purchase(product_id: String, purchase_token: String):
	pending_purchases.append({
		"product_id": product_id,
		"purchase_token": purchase_token,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	var save_data = {
		"pending_purchases": pending_purchases
	}
	LocalData.saveData("pending_payments.dat", save_data)

func load_pending_purchases():
	var data = LocalData.loadData("pending_payments.dat")
	if data and data.has("pending_purchases"):
		pending_purchases = data.pending_purchases
		retry_pending_purchases()

func remove_pending_purchase(purchase_token: String):
	for i in range(pending_purchases.size() - 1, -1, -1):
		if pending_purchases[i].purchase_token == purchase_token:
			pending_purchases.remove_at(i)
	
	var save_data = {
		"pending_purchases": pending_purchases
	}
	LocalData.saveData("pending_payments.dat", save_data)

func retry_pending_purchases():
	if pending_purchases.is_empty():
		return
	
	print("Retrying ", pending_purchases.size(), " pending purchases")
	
	for purchase in pending_purchases.duplicate():
		await verify_purchase_with_server(purchase.product_id, purchase.purchase_token)
		await get_tree().create_timer(1.0).timeout

func clear_old_pending_purchases():
	var current_time = Time.get_unix_time_from_system()
	var max_age = 86400 * 7
	
	for i in range(pending_purchases.size() - 1, -1, -1):
		var purchase = pending_purchases[i]
		if current_time - purchase.timestamp > max_age:
			print("Removing old pending purchase: ", purchase.product_id)
			pending_purchases.remove_at(i)
	
	var save_data = {
		"pending_purchases": pending_purchases
	}
	LocalData.saveData("pending_payments.dat", save_data)
