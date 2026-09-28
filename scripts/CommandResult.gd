extends RefCounted
class_name CommandResult

## 指令执行结果（5A）。
##
## 所有 execute_command 都返回这个对象，而不是裸 bool —— 因为联机模式下
## 客户端需要拿到「为什么被拒绝」的中文原因并显示给玩家。

## 是否执行成功
var ok: bool = false
## 失败原因（中文，可直接显示给玩家）；成功时为空串
var reason: String = ""
## 状态是否真的发生了变化（用于判断要不要广播新状态）
var state_changed: bool = false


func _init(p_ok: bool = false, p_reason: String = "", p_state_changed: bool = false) -> void:
	ok = p_ok
	reason = p_reason
	state_changed = p_state_changed


static func success(p_state_changed: bool = true) -> CommandResult:
	return CommandResult.new(true, "", p_state_changed)


static func fail(p_reason: String) -> CommandResult:
	return CommandResult.new(false, p_reason, false)


func to_dict() -> Dictionary:
	return {"ok": ok, "reason": reason, "state_changed": state_changed}


static func from_dict(data: Dictionary) -> CommandResult:
	return CommandResult.new(
		bool(data.get("ok", false)),
		str(data.get("reason", "")),
		bool(data.get("state_changed", false)))
