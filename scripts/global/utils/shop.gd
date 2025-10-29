extends Control

@onready var products_container = $Panel/VBoxContainer/ScrollContainer/ProductsGrid
@onready var currency_label = $Panel/VBoxContainer/TopBar/CurrencyLabel
@onready var loading_label = $Panel/VBoxContainer/LoadingLabel
@onready var purchase_button_scene = preload("res://scenes/PurchaseButton.tscn")

var available_products = []
var current_currency = 0

func _ready():
	if not get_tree().root.has_node("PaymentManager"):
		var payment_manager = preload("res://scripts/PaymentManager.gd").new()
		payment_manager.name = "PaymentManager"
		get_tree().root.add_child(payment_manager)
	
	var payment_manager = get_tree().root.get_node("PaymentManager")
	payment_manager.purchase_success.connect(_on_purchase_success)
	payment_manager.purchase_failed.connect(_on_purchase_failed)
	
	await load_shop_data()

func load_shop_data():
	loading_label.visible = true
	products_container.visible = false
	
	current_currency = await Client.getCurrency(Global.user_id, Global.token)
	update_currency_display()
	
	var payment_manager = get_tree().root.get_node("PaymentManager")
	available_products = await payment_manager.get_available_products()
	
	if available_products.is_empty():
		loading_label.text = "Failed to load products"
		return
	
	display_products()
	loading_label.visible = false
	products_container.visible = true

func display_products():
	for child in products_container.get_children():
		child.queue_free()
	
	for product in available_products:
		var button = purchase_button_scene.instantiate()
		products_container.add_child(button)
		
		button.set_product_data(
			product.product_id,
			product.amount,
			product.price_usd
		)
		
		button.pressed.connect(_on_product_selected.bind(product.product_id))

func _on_product_selected(product_id: String):
	var payment_manager = get_tree().root.get_node("PaymentManager")
	payment_manager.purchase_product(product_id)
	
	show_purchase_dialog("Processing purchase...")

func _on_purchase_success(product_id: String, currency_awarded: int):
	current_currency += currency_awarded
	update_currency_display()
	
	show_success_dialog("Purchase successful!\nReceived: " + str(currency_awarded) + " coins")

func _on_purchase_failed(error_message: String):
	show_error_dialog("Purchase failed: " + error_message)

func update_currency_display():
	currency_label.text = "Coins: " + Client.format_number(current_currency)

func show_purchase_dialog(message: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Processing"
	add_child(dialog)
	dialog.popup_centered()

func show_success_dialog(message: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Success"
	add_child(dialog)
	dialog.popup_centered()
	await dialog.confirmed
	dialog.queue_free()

func show_error_dialog(message: String):
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Error"
	add_child(dialog)
	dialog.popup_centered()
	await dialog.confirmed
	dialog.queue_free()

func _on_watch_ad_button_pressed():
	var payment_manager = get_tree().root.get_node("PaymentManager")
	payment_manager.ad_reward_success.connect(_on_ad_reward_success)
	payment_manager.ad_reward_failed.connect(_on_ad_reward_failed)
	
	show_purchase_dialog("Loading ad...")
	await payment_manager.watch_ad_for_reward()

func _on_ad_reward_success(reward_amount: int):
	current_currency += reward_amount
	update_currency_display()
	show_success_dialog("Ad reward claimed!\nReceived: " + str(reward_amount) + " coins")

func _on_ad_reward_failed(error_message: String):
	show_error_dialog("Ad reward failed: " + error_message)

func _on_history_button_pressed():
	var payment_manager = get_tree().root.get_node("PaymentManager")
	var history = await payment_manager.get_payment_history()
	
	if history.is_empty():
		show_error_dialog("No payment history")
		return
	
	var history_text = "Payment History:\n\n"
	for payment in history:
		var date = Time.get_datetime_string_from_unix_time(payment.created)
		history_text += date + " - " + payment.product_id + "\n"
		history_text += "Amount: $" + str(payment.amount / 100.0) + "\n"
		history_text += "Currency: " + str(payment.currency_awarded) + "\n"
		history_text += "Verified: " + ("Yes" if payment.verified else "No") + "\n\n"
	
	show_success_dialog(history_text)
