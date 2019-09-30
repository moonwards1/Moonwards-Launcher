extends Node

onready var http_request : HTTPRequest = $HTTPRequest
onready var text_log = $TextLog
onready var progress_bar = $ProgressBar
onready var status = $HBoxContainer/VBoxContainer/Status
onready var launch_button = $HBoxContainer/VBoxContainer/LaunchButton
onready var update_button = $HBoxContainer/VBoxContainer/UpdateButton

var server_url : String = "http://107.173.129.154/moonwards/"
var download_queue : Array = []
var downloads_done : Array = []
var file : File = File.new()
var directory : Directory = Directory.new()

signal receive_update_message

func _ready():
	launch_button.hide()
	update_button.hide()
	_check_for_updates()
	set_process(false)

func _process(delta):
	if download_queue.size() != 0:
		var body_size = http_request.get_body_size()
		var downloaded_bytes = http_request.get_downloaded_bytes()
		
		var percent_current_file = int(downloaded_bytes * 100 / body_size)
		var percent_per_download = 100.0 / (download_queue.size() + downloads_done.size())
		var percent_done = downloads_done.size() * percent_per_download
		
		var new_value = percent_done + (percent_per_download * (percent_current_file / 100.0))
		progress_bar.value = new_value

func _log(var text):
	emit_signal("receive_update_message", text)
	text_log.text += text + "\n"

func _receive_file(result, response_code, headers, body):
	_log("result " + str(response_code) + ".")
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_log("An error occured getting the an update.")
		_get_next_update()
		return
	
	if response_code != HTTPClient.RESPONSE_OK:
		_set_status("Error")
		_log("Received response code " + str(response_code) + ".")
	else:
		var write_path = "user://" + download_queue[0]
		file.open(write_path, File.WRITE)
		file.store_buffer(body)
		file.close()
		_log("Done writing " + "user://" + download_queue[0])
	
	downloads_done.append(download_queue[0])
	download_queue.remove(0)
	_get_next_update()

func _get_next_update():
	if download_queue.size() != 0:
		_log("Start download of file: " + download_queue[0])
		_set_status("Downloading...")
		
		http_request.connect("request_completed", self, "_receive_file")
		
		var error = http_request.request(server_url + download_queue[0])
		if error != OK:
			_set_status("Error")
			_log("Error " + str(error) + " requesting update " + server_url + download_queue[0])
	else:
		_set_status("Update done")
		launch_button.show()

func _set_status(text : String):
	status.text = text

func _check_for_updates():
	http_request.connect("request_completed", self, "_receive_md5_json")
	var error = http_request.request(server_url + "md5_list.json")
	
	if error != OK:
		_set_status("Error")
		_log("Error retrieving update list!")
		return

func _receive_md5_json(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Error")
		_log("An error occured getting the update list!")
		return
	
	var json = JSON.parse(body.get_string_from_utf8())
	if json.error != OK:
		_set_status("Error")
		_log("Error parsing update list!")
		_log(json.error_string)
		return
	
	for file_data in json.result["files"]:
		var file_name = file_data["file"]
		var file_md5 = file_data["md5"]
		
		_log("File : " + file_name + " md5: " + file_md5)
		if directory.file_exists("user://" + file_name):
			var local_md5 = file.get_md5("user://" + file_name)
			if local_md5 != file_md5:
				download_queue.append(file_name)
		else:
			download_queue.append(file_name)
	
	if download_queue.size() != 0:
		_set_status("Updates Available")
		update_button.show()
	else:
		_set_status("Ready")
		launch_button.show()
	
	http_request.disconnect("request_completed", self, "_receive_md5_json")

func _start_update():
	update_button.hide()
	_get_next_update()
	set_process(true)

func _launch_moonwards():
	var output = []
	OS.execute('/bin/sh', ["-c", "cd " + OS.get_user_data_dir() + " && ./MoonTown.x86_64"], false, output)
	get_tree().quit()