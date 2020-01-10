extends Node

enum PLATFORMS {
	NONE
	LINUX,
	OSX,
	WINDOWS
	}

enum UPDATE_STATE{
	NONE,
	LAUNCHER,
	MOONWARDS
	}

onready var http_request : HTTPRequest = $HTTPRequest
onready var text_log = $TextLog
onready var progress_bar = $ProgressBar
onready var status = $HBoxContainer/VBoxContainer/Status
onready var launch_button = $HBoxContainer/VBoxContainer/LaunchButton
onready var update_moonwards_button = $HBoxContainer/VBoxContainer/UpdateMoonwardsButton
onready var update_launcher_button = $HBoxContainer/VBoxContainer/UpdateLauncherButton

var server_url : String = "http://launcher.moonwards.com/"
var download_queue : Array = []
var md5_queue : Array = []
var downloads_done : Array = []
var file : File = File.new()
var directory : Directory = Directory.new()
var platform : int = PLATFORMS.NONE
var update_state : int = UPDATE_STATE.NONE
var update_state_name : String = "NA"

signal receive_update_message

func _input(event):
	if event.is_action_pressed("toggle_log"):
		text_log.visible = !text_log.visible

func _ready() -> void:
	http_request.use_threads = true
	launch_button.hide()
	update_moonwards_button.hide()
	update_launcher_button.hide()
	set_process(false)
	
	_platform_check()
	_check_for_launcher_updates()

func _check_for_launcher_updates() -> void:
	http_request.connect("request_completed", self, "_receive_files_json")
	var error = http_request.request(server_url + "launcher_files.json")
	
	update_state = UPDATE_STATE.LAUNCHER
	update_state_name = "launcher"
	
	if error != OK:
		_set_status("Error getting launcher updates.")
		return

func _receive_files_json(result : int, response_code : int, headers : PoolStringArray, body : PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Error, could not fetch " + update_state_name + " updates.")
		_log("Error status " + str(result))
		return
	
	var json = JSON.parse(body.get_string_from_utf8())
	if json.error != OK:
		_set_status("Error parsing " + update_state_name + " update list.")
		_log(json.error_string)
		return
	
	var json_result = json.result
	var path
	var files
	if platform == PLATFORMS.LINUX:
		files = json_result.X11["files"]
		path = json_result.X11["path"]
	elif platform == PLATFORMS.WINDOWS:
		files = json_result.Windows["files"]
		path = json_result.Windows["path"]
	elif platform == PLATFORMS.OSX:
		files = json_result.OSX["files"]
		path = json_result.OSX["path"]
	else:
		_set_status("Platform not supported.")
		return
	
	for file_name in files:
		md5_queue.append({"file_name" : file_name, "path" : path})
	
	http_request.disconnect("request_completed", self, "_receive_files_json")

	_get_next_md5()

func _get_next_md5() -> void:
	if md5_queue.size() != 0:
		http_request.connect("request_completed", self, "_receive_md5")
		
		var error = http_request.request(server_url + md5_queue[0].path + md5_queue[0].file_name + ".md5")
		if error != OK:
			_set_status("Error")
			_log("Error " + str(error) + " requesting update " + server_url + md5_queue[0].path + md5_queue[0].file_name + ".md5")
	else:
		if download_queue.size() != 0:
			if update_state == UPDATE_STATE.LAUNCHER:
				_set_status("Launcher Updates Available")
				update_launcher_button.show()
			elif update_state == UPDATE_STATE.MOONWARDS:
				_set_status("Moonwards Updates Available")
				update_moonwards_button.show()
		else:
			if update_state == UPDATE_STATE.LAUNCHER:
				_log("No launcher updates available.")
				_check_for_moonwards_updates()
			elif update_state == UPDATE_STATE.MOONWARDS:
				_log("No Moonwards updates available.")
				launch_button.show()

func _receive_md5(result : int, response_code : int, headers : PoolStringArray, body : PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_log("An error occured getting the MD5.")
		_get_next_md5()
		return
	
	if response_code != HTTPClient.RESPONSE_OK:
		_set_status("Error getting MD5.")
		_log("Received response code " + str(response_code) + ".")
	else:
		var file_md5 = body.get_string_from_utf8().rstrip("\n")
		var file_name = md5_queue[0].file_name
		var path = md5_queue[0].path
		
		_log("File : " + file_name + " md5: " + file_md5)
		
		var write_dir
		if update_state == UPDATE_STATE.LAUNCHER:
			write_dir = "res://"
		elif update_state == UPDATE_STATE.MOONWARDS:
			write_dir = "user://"

		if directory.file_exists(write_dir + file_name):
			var local_md5 = file.get_md5(write_dir + file_name)
			_log("Local md5: " + local_md5)
			if local_md5 != file_md5:
				download_queue.append({"file_name" : file_name, "path" : path})
		else:
			_log("File : " + file_name + " does not exist")
			download_queue.append({"file_name" : file_name, "path" : path})
	
	http_request.disconnect("request_completed", self, "_receive_md5")
	
	md5_queue.remove(0)
	_get_next_md5()

func _check_for_moonwards_updates() -> void:
	http_request.connect("request_completed", self, "_receive_files_json")
	var error = http_request.request(server_url + "moonwards/moonwards_files.json")
	
	update_state = UPDATE_STATE.MOONWARDS
	update_state_name = "Moonwards"
	
	if error != OK:
		_set_status("Error getting Moonwards updates.")
		return

func _process(delta : float) -> void:
	if download_queue.size() != 0:
		var body_size = http_request.get_body_size()
		var downloaded_bytes = http_request.get_downloaded_bytes()
		
		var percent_current_file = int(downloaded_bytes * 100 / body_size)
		var percent_per_download = 100.0 / (download_queue.size() + downloads_done.size())
		var percent_done = downloads_done.size() * percent_per_download
		
		var new_value = percent_done + (percent_per_download * (percent_current_file / 100.0))
		progress_bar.value = new_value

func _platform_check() -> void:
	var platform_name = OS.get_name()
	if platform_name == "X11":
		platform = PLATFORMS.LINUX
	elif platform_name == "Windows":
		platform = PLATFORMS.WINDOWS
	elif platform_name == "OSX":
		platform = PLATFORMS.OSX

func _log(text : String) -> void:
	emit_signal("receive_update_message", text)
	text_log.text += text + "\n"
	print(text)

func _receive_file(result : int, response_code : int, headers : PoolStringArray, body : PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_log("An error occured getting an update.")
		_get_next_update()
		return
	
	if response_code != HTTPClient.RESPONSE_OK:
		_set_status("Error downloading file.")
		_log("Received response code " + str(response_code) + ".")
	else:
		var write_dir
		if update_state == UPDATE_STATE.LAUNCHER:
			write_dir = "res://" + download_queue[0].file_name
		elif update_state == UPDATE_STATE.MOONWARDS:
			write_dir = "user://" + download_queue[0].file_name
		
		file.open(write_dir, File.WRITE)
		file.store_buffer(body)
		file.close()
		_log("Done writing " + write_dir)
	
	http_request.disconnect("request_completed", self, "_receive_file")
	
	downloads_done.append(download_queue[0])
	download_queue.remove(0)
	_get_next_update()

func _get_next_update() -> void:
	if download_queue.size() != 0:
		_log("Start download of file: " + download_queue[0].file_name)
		_set_status("Downloading...")
		
		http_request.connect("request_completed", self, "_receive_file")
		
		var error = http_request.request(server_url + download_queue[0].path + download_queue[0].file_name)
		if error != OK:
			_set_status("Error")
			_log("Error " + str(error) + " requesting update " + server_url + download_queue[0].path + download_queue[0].file_name)
	else:
		if update_state == UPDATE_STATE.LAUNCHER:
			_restart_launcher()
		elif update_state == UPDATE_STATE.MOONWARDS:
			_set_status("Update done")
			launch_button.show()

func _restart_launcher() -> void:
	var output = []
	var pid
	
	if platform == PLATFORMS.LINUX:
		pid = OS.execute('/bin/sh', ["-c", "chmod +x Moonwards-Launcher.x86_64 && ./Moonwards-Launcher.x86_64"], false, output)
	elif platform == PLATFORMS.OSX:
		pid = OS.execute("./Moonwards-Launcher.app", [], false, output)
	elif platform == PLATFORMS.WINDOWS:
		pid = OS.execute("./Moonwards-Launcher.exe", [], false, output)
	
	if pid == -1:
		_set_status("Error executing " + update_state_name + " : " + str(pid))
	else:
		get_tree().quit()

func _set_status(text : String) -> void:
	_log(text)
	status.text = text

func _launch_moonwards() -> void:
	var output = []
	var pid
	
	if platform == PLATFORMS.LINUX:
		var user_data_dir = OS.get_user_data_dir().replace(" ", "\\ ")
		pid = OS.execute('/bin/sh', ["-c", "cd " + user_data_dir + " && chmod +x MoonTown.x86_64 && ./MoonTown.x86_64"], false, output)
	elif platform == PLATFORMS.OSX:
		pid = OS.execute('/bin/sh', ["-c", "cd " + OS.get_user_data_dir() + " && ./MoonTown.app"], false, output)
	elif platform == PLATFORMS.WINDOWS:
		pid = OS.execute('CMD.exe', ["/C", "cd " + OS.get_user_data_dir() + " && ./MoonTown.exe"], false, output)
	
	if pid == -1:
		_set_status("Error launching Moonwards : " + str(pid))
	else:
		get_tree().quit()

func _update_launcher() -> void:
	update_launcher_button.hide()
	_get_next_update()
	set_process(true)

func _update_moonwards() -> void:
	update_moonwards_button.hide()
	_get_next_update()
	set_process(true)
