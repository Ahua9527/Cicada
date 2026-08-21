#!/usr/bin/env python3
# 生成 Cicada 远程控制 iOS 快捷指令（未签名 .shortcut 二进制 plist）。
# 用法：CICADA_SC_TOKEN=<token> python3 apps/relay/scripts/generate-shortcuts.py [输出目录]
# 要求：Python 3.9+ 标准库；token 来自 `cicada shortcut create`；生成后用
#   `shortcuts sign -m anyone -i <in> -o <out>` 签名即可 AirDrop 到 iPhone 导入。
# 注意：生成的 .shortcut 文件内嵌 token，输出目录默认 ~/.cicada/shortcuts（不要提交）。

import json
import os
import plistlib
import sys
import uuid

RELAY_URL = os.environ.get("CICADA_RELAY_URL", "https://cicada-relay.ahua.space")
ENDPOINT = RELAY_URL.rstrip("/") + "/v1/shortcuts/command"
TOKEN = os.environ.get("CICADA_SC_TOKEN") or sys.exit("需要 CICADA_SC_TOKEN 环境变量")


def default_device_id() -> str:
    try:
        with open(os.path.expanduser("~/.cicada/config.json")) as f:
            return json.load(f)["deviceId"]
    except Exception:
        return "MAC_0123456789ABCDEF0123456789ABCDEF"


DEVICE_ID = os.environ.get("CICADA_DEVICE_ID", default_device_id())
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.cicada/shortcuts")

CONTENT_ITEM_CLASSES = [
    "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem",
    "WFDateContentItem", "WFEmailAddressContentItem", "WFGenericFileContentItem",
    "WFImageContentItem", "WFiTunesProductContentItem", "WFLocationContentItem",
    "WFDCMapsLinkContentItem", "WFAVAssetContentItem", "WFPDFContentItem",
    "WFPhoneNumberContentItem", "WFRichTextContentItem", "WFSafariWebPageContentItem",
    "WFStringContentItem", "WFURLContentItem",
]

# 图标配色（Shortcuts 内置调色板整数值）
COLORS = {
    "blue": 463140863, "teal": 3980825855, "green": 4292093695, "yellow": 4294954495,
    "orange": 431817727, "red": 4282601983, "purple": 2071128575, "gray": 2846468607,
}


def _uuid() -> str:
    return str(uuid.uuid4()).upper()


def dict_param(items: list) -> dict:
    """构造 WFDictionaryFieldValue 参数。items: (key, value) 列表，value 为 str 或嵌套 dict。"""
    field_items = []
    for key, value in items:
        if isinstance(value, dict) and value.get("WFSerializationType") == "WFTextTokenAttachment":
            field_items.append({"WFItemType": 0, "WFKey": key, "WFValue": value})
        elif isinstance(value, dict):
            field_items.append({
                "WFItemType": 1, "WFKey": key,
                "WFValue": {"Value": {"WFDictionaryFieldValueItems": value["items"]}},
            })
        else:
            field_items.append({"WFItemType": 0, "WFKey": key, "WFValue": value})
    return {
        "WFSerializationType": "WFDictionaryFieldValue",
        "Value": {"WFDictionaryFieldValueItems": field_items},
    }


def action_output(output_uuid: str) -> dict:
    return {
        "WFSerializationType": "WFTextTokenAttachment",
        "Value": {"Type": "ActionOutput", "OutputUUID": output_uuid},
    }


def post_action(command: str, extra_params=None):
    """Get Contents of URL：POST 命令到 relay。返回 (action, action_uuid)。"""
    action_uuid = _uuid()
    body_items = [
        ("device_id", DEVICE_ID),
        ("command", command),
        ("request_id", f"iphone-{command}"),
    ]
    if extra_params:
        body_items.append(("params", {"items": extra_params}))
    action = {
        "WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFURL": ENDPOINT,
            "WFHTTPMethod": "POST",
            "WFHTTPHeaders": dict_param([
                ("Authorization", f"Bearer {TOKEN}"),
                ("Content-Type", "application/json"),
            ]),
            "WFHTTPBodyType": "JSON",
            "WFJSONValues": dict_param(body_items),
        },
    }
    return action, action_uuid


def extract_message_action(input_uuid: str):
    """Get Dictionary Value：从指定动作的输出取 message 字段。"""
    return extract_key_action("message", input_uuid)


def extract_key_action(key: str, input_uuid: str):
    """Get Dictionary Value：从指定动作的输出（而非上一动作）取指定键。"""
    action_uuid = _uuid()
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFInput": action_output(input_uuid),
            "WFDictionaryKey": key,
            "WFGetDictionaryValueType": "Value",
        },
    }, action_uuid


def text_action(text_uuids: list):
    """「文本」动作：把多个变量拼成一段文本（Shortcuts 最可靠的变量拼装模式）。"""
    action_uuid = _uuid()
    if len(text_uuids) == 1:
        string = "\ufffc"
        ranges = {"{0, 1}": {"Type": "ActionOutput", "OutputUUID": text_uuids[0]}}
    else:
        string = "\ufffc\n\ufffc"
        ranges = {
            "{0, 1}": {"Type": "ActionOutput", "OutputUUID": text_uuids[0]},
            "{2, 3}": {"Type": "ActionOutput", "OutputUUID": text_uuids[1]},
        }
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.gettext",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFTextActionText": {
                "WFSerializationType": "WFTextTokenString",
                "Value": {"string": string, "attachmentsByRange": ranges},
            },
        },
    }, action_uuid


def notify_from_text_action(text_action_uuid: str, title: str) -> dict:
    """通知正文直接引用「文本」动作的输出（不再内嵌多附件字符串）。"""
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.notification",
        "WFWorkflowActionParameters": {
            "WFNotificationActionTitle": title,
            "WFNotificationActionBody": {
                "WFSerializationType": "WFTextTokenString",
                "Value": {
                    "string": "\ufffc",
                    "attachmentsByRange": {
                        "{0, 1}": {"Type": "ActionOutput", "OutputUUID": text_action_uuid}
                    },
                },
            },
        },
    }


def notify_static_action(title: str, body: str) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.notification",
        "WFWorkflowActionParameters": {
            "WFNotificationActionTitle": title,
            "WFNotificationActionBody": body,
        },
    }


def ask_number_action(prompt: str) -> tuple[dict, str]:
    action_uuid = _uuid()
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.ask",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFAskActionPrompt": prompt,
            "WFAskActionType": "Number",
        },
    }, action_uuid


def calculate_divide_action(input_uuid: str, divisor: int) -> tuple[dict, str]:
    action_uuid = _uuid()
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.math",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFMathOperation": "÷",
            "WFMathOperand": divisor,
            "WFInput": action_output(input_uuid),
        },
    }, action_uuid


def build_workflow(name: str, color: str, actions: list) -> dict:
    return {
        "WFWorkflowClientVersion": "1347.27",
        "WFWorkflowClientRelease": "7.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": COLORS[color],
            "WFWorkflowIconGlyphNumber": 61446,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": ["NCWidget", "WatchKit"],
        "WFWorkflowInputContentItemClasses": CONTENT_ITEM_CLASSES,
        "WFWorkflowActions": actions,
    }


def result_actions(command: str, extra_params=None):
    """POST + 提取 message/data + 文本拼装 + 通知。
    返回 (actions, post_uuid)——调用方需要自定义后续时取 post_uuid。"""
    post, post_uuid = post_action(command, extra_params)
    extract_msg, msg_uuid = extract_message_action(post_uuid)
    extract_data, data_uuid = extract_key_action("data", post_uuid)
    text, text_uuid = text_action([msg_uuid, data_uuid])
    return [post, extract_msg, extract_data, text,
            notify_from_text_action(text_uuid, "Cicada")], post_uuid


def simple_command_actions(command: str) -> list:
    actions, _ = result_actions(command)
    return actions


def percent_command_actions(command: str, prompt: str) -> list:
    ask, ask_uuid = ask_number_action(prompt)
    calc, calc_uuid = calculate_divide_action(ask_uuid, 100)
    post, post_uuid = post_action(command, [("level", action_output(calc_uuid))])
    extract_msg, msg_uuid = extract_message_action(post_uuid)
    extract_data, data_uuid = extract_key_action("data", post_uuid)
    text, text_uuid = text_action([msg_uuid, data_uuid])
    return [ask, calc, post, extract_msg, extract_data, text,
            notify_from_text_action(text_uuid, "Cicada")]


def screenshot_actions() -> list:
    """截屏：daemon 回传 image_base64（JPEG），解码后存入相册。"""
    post, post_uuid = post_action("screenshot")
    get_data, data_uuid = extract_key_action("data", post_uuid)
    get_b64, b64_uuid = extract_key_action("image_base64", data_uuid)
    decode_uuid = _uuid()
    decode = {
        "WFWorkflowActionIdentifier": "is.workflow.actions.base64encode",
        "WFWorkflowActionParameters": {
            "UUID": decode_uuid,
            "WFEncodeMode": "Decode",
            "WFInput": action_output(b64_uuid),
        },
    }
    save = {
        "WFWorkflowActionIdentifier": "is.workflow.actions.savetocameraroll",
        "WFWorkflowActionParameters": {"WFInput": action_output(decode_uuid)},
    }
    return [post, get_data, get_b64, decode, save,
            notify_static_action("Cicada", "截图已存入相册（Mac 原件在 ~/.cicada/screenshots）")]


# ---------- 菜单动作 ----------

def menu_begin(title: str, items: list) -> dict:
    """「从菜单中选取」起始（WFControlFlowMode=0）。items 为菜单项标题列表。"""
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.choosefrommenu",
        "WFWorkflowActionParameters": {
            "WFControlFlowMode": 0,
            "WFMenuActionTitle": title,
            "WFMenuItems": items,
        },
    }


def menu_item_begin(title: str) -> dict:
    """菜单项内容块起始（WFControlFlowMode=1）。"""
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.choosefrommenu",
        "WFWorkflowActionParameters": {
            "WFControlFlowMode": 1,
            "WFMenuItemTitle": title,
        },
    }


def menu_end() -> dict:
    """菜单结束（WFControlFlowMode=2）。"""
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.choosefrommenu",
        "WFWorkflowActionParameters": {"WFControlFlowMode": 2},
    }


# ---------- 命令分组（单指令与菜单共用同一份数据） ----------
# (叶子标题, 命令, 颜色, 动作列表)
GROUPS: list = [
    ("状态查询", [
        ("Ping", "ping", "gray", simple_command_actions("ping")),
        ("系统状态", "status", "blue", simple_command_actions("status")),
        ("安防状态", "sentry_status", "red", simple_command_actions("sentry_status")),
    ]),
    ("屏幕与锁", [
        ("锁屏", "lock", "red", simple_command_actions("lock")),
        ("截屏", "screenshot", "blue", screenshot_actions()),
    ]),
    ("音量", [
        ("静音", "mute", "orange", simple_command_actions("mute")),
        ("取消静音", "unmute", "orange", simple_command_actions("unmute")),
        ("音量加", "volume_up", "green", simple_command_actions("volume_up")),
        ("音量减", "volume_down", "green", simple_command_actions("volume_down")),
        ("音量设置", "volume_set", "green",
         percent_command_actions("volume_set", "音量百分比（0-100）")),
    ]),
    ("亮度", [
        ("亮度加", "brightness_up", "yellow", simple_command_actions("brightness_up")),
        ("亮度减", "brightness_down", "yellow", simple_command_actions("brightness_down")),
        ("亮度设置", "brightness_set", "yellow",
         percent_command_actions("brightness_set", "亮度百分比（0-100）")),
    ]),
    ("电源", [
        ("退出蝉", "daemon_exit", "red", simple_command_actions("daemon_exit")),
    ]),
]


def build_menu_actions() -> list:
    """两级菜单装配：主菜单 → 分组子菜单 → 叶子命令动作。"""
    actions = [menu_begin("蝉·远程控制", [group for group, _ in GROUPS])]
    for group, leaves in GROUPS:
        actions.append(menu_item_begin(group))
        actions.append(menu_begin(group, [title for title, _, _, _ in leaves]))
        for title, _command, _color, leaf_actions in leaves:
            actions.append(menu_item_begin(title))
            actions.extend(leaf_actions)
        actions.append(menu_end())
    actions.append(menu_end())
    return actions


MENU_SHORTCUT_NAME = "蝉·远程控制"


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    count = 0
    # 1) 独立单指令（可放主屏幕一键直达）
    for _group, leaves in GROUPS:
        for title, _command, color, actions in leaves:
            workflow = build_workflow(f"蝉·{title}", color, actions)
            path = os.path.join(OUT_DIR, f"蝉·{title}.shortcut")
            with open(path, "wb") as f:
                plistlib.dump(workflow, f, fmt=plistlib.FMT_BINARY)
            print(f"生成 {path}")
            count += 1
    # 2) 多级菜单合一版
    menu_workflow = build_workflow(MENU_SHORTCUT_NAME, "blue", build_menu_actions())
    menu_path = os.path.join(OUT_DIR, f"{MENU_SHORTCUT_NAME}.shortcut")
    with open(menu_path, "wb") as f:
        plistlib.dump(menu_workflow, f, fmt=plistlib.FMT_BINARY)
    print(f"生成 {menu_path}  [两级菜单，共 {count} 个操作]")
    count += 1
    print(f"\n共 {count} 个。签名：")
    print(f"  for f in '{OUT_DIR}'/*.shortcut; do")
    print("    shortcuts sign -m anyone -i \"$f\" -o \"${f%.shortcut}-signed.shortcut\"; done")


if __name__ == "__main__":
    main()
