extends Control

@export var dialogTitle: String = "Disconnected"
@export var primaryMsg: String = "You have been kicked due to unexpected client behavior."
@export var errorCode: String = "Error Code: 268"
@export var btnText: String = "Leave" 

@export var titleLbl: Label
@export var primaryLbl: Label
@export var errorLbl: Label
@export var leaveBtn: Button

@export var binded = false

signal leavePressed

func _ready():
	updateDialog()

func updateDialog():
	if titleLbl:
		titleLbl.text = dialogTitle
	if primaryLbl:
		primaryLbl.text = primaryMsg
	if errorLbl:
		errorLbl.text = "(" + errorCode + ")"
	if leaveBtn:
		leaveBtn.text = btnText

func _on_disconnect_pressed() -> void:
	Global.alrHasError = false
	leavePressed.emit()
	if !binded:
		Client.disconnect_from_server()
	queue_free() 
