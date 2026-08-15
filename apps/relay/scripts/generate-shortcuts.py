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


def extract_message_action() -> tuple[dict, str]:
    """Get Dictionary Value：取响应里的 message 字段。"""
    action_uuid = _uuid()
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFDictionaryKey": "message",
            "WFGetDictionaryValueType": "Value",
        },
    }, action_uuid


def notify_action(body_output_uuid: str, title: str) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.notification",
        "WFWorkflowActionParameters": {
            "WFNotificationActionTitle": title,
            "WFNotificationActionBody": {
                "WFSerializationType": "WFTextTokenString",
                "Value": {
                    "string": "￼",
                    "attachmentsByRange": {
                        "{0, 1}": {
                            "Type": "ActionOutput",
                            "OutputUUID": body_output_uuid,
                        }
                    },
                },
            },
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


def ask_text_action(prompt: str) -> tuple[dict, str]:
    action_uuid = _uuid()
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.ask",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFAskActionPrompt": prompt,
            "WFAskActionType": "Text",
        },
    }, action_uuid


def calculate_divide_action(input_uuid: str, divisor: int) -> tuple[dict, str]:
    action_uuid = _uuid()
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.calculate",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFMathOperation": "÷",
            "WFMathOperand2": divisor,
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


def simple_command_actions(command: str) -> list:
    post, _ = post_action(command)
    extract, extract_uuid = extract_message_action()
    return [post, extract, notify_action(extract_uuid, "Cicada")]


def percent_command_actions(command: str, prompt: str) -> list:
    ask, ask_uuid = ask_number_action(prompt)
    calc, calc_uuid = calculate_divide_action(ask_uuid, 100)
    post, _ = post_action(command, [("level", action_output(calc_uuid))])
    extract, extract_uuid = extract_message_action()
    return [ask, calc, post, extract, notify_action(extract_uuid, "Cicada")]


def app_open_actions() -> list:
    ask, ask_uuid = ask_text_action("应用名（如 Calculator / 微信）")
    post, _ = post_action("app_open", [("name", action_output(ask_uuid))])
    extract, extract_uuid = extract_message_action()
    return [ask, post, extract, notify_action(extract_uuid, "Cicada")]


# (文件名, 显示命令, 颜色, 动作构造)
SHORTCUTS: list[tuple[str, str, str, list]] = [
    ("蝉·Ping", "ping", "gray", simple_command_actions("ping")),
    ("蝉·系统状态", "status", "blue", simple_command_actions("status")),
    ("蝉·锁屏", "lock", "red", simple_command_actions("lock")),
    ("蝉·屏幕休眠", "sleep_displays", "purple", simple_command_actions("sleep_displays")),
    ("蝉·唤醒屏幕", "wake", "yellow", simple_command_actions("wake")),
    ("蝉·静音", "mute", "orange", simple_command_actions("mute")),
    ("蝉·取消静音", "unmute", "orange", simple_command_actions("unmute")),
    ("蝉·音量加", "volume_up", "green", simple_command_actions("volume_up")),
    ("蝉·音量减", "volume_down", "green", simple_command_actions("volume_down")),
    ("蝉·音量设置", "volume_set", "green",
     percent_command_actions("volume_set", "音量百分比（0-100）")),
    ("蝉·亮度加", "brightness_up", "yellow", simple_command_actions("brightness_up")),
    ("蝉·亮度减", "brightness_down", "yellow", simple_command_actions("brightness_down")),
    ("蝉·亮度设置", "brightness_set", "yellow",
     percent_command_actions("brightness_set", "亮度百分比（0-100）")),
    ("蝉·防休眠开", "caffeinate", "teal", simple_command_actions("caffeinate")),
    ("蝉·防休眠关", "decaffeinate", "teal", simple_command_actions("decaffeinate")),
    ("蝉·截屏", "screenshot", "blue", simple_command_actions("screenshot")),
    ("蝉·运行中应用", "app_list", "blue", simple_command_actions("app_list")),
    ("蝉·打开应用", "app_open", "purple", app_open_actions()),
    ("蝉·安防开", "sentry_start", "red", simple_command_actions("sentry_start")),
    ("蝉·安防关", "sentry_stop", "red", simple_command_actions("sentry_stop")),
    ("蝉·安防状态", "sentry_status", "red", simple_command_actions("sentry_status")),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, command, _color, actions in SHORTCUTS:
        workflow = build_workflow(name, _color, actions)
        path = os.path.join(OUT_DIR, f"{name}.shortcut")
        with open(path, "wb") as f:
            plistlib.dump(workflow, f, fmt=plistlib.FMT_BINARY)
        print(f"生成 {path}  [{command}]")
    print(f"\n共 {len(SHORTCUTS)} 个。签名：")
    print(f"  for f in '{OUT_DIR}'/*.shortcut; do")
    print("    shortcuts sign -m anyone -i \"$f\" -o \"${f%.shortcut}-signed.shortcut\"; done")


if __name__ == "__main__":
    main()
