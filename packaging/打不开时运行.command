#!/bin/zsh

set -u

APP_PATH="/Applications/筛图神器.app"

show_message() {
    /usr/bin/osascript -e "display dialog \"$1\" buttons {\"好\"} default button \"好\" with title \"筛图神器\""
}

if [[ ! -d "$APP_PATH" ]]; then
    show_message "请先把“筛图神器.app”拖入“应用程序”文件夹，再运行此脚本。"
    exit 1
fi

echo "正在修复：$APP_PATH"

# Only remove the download quarantine attribute from the installed app.
/usr/bin/xattr -r -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true

if ! /usr/bin/codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    echo "正在修复应用签名..."
    if ! /usr/bin/codesign --force --deep --sign - "$APP_PATH"; then
        show_message "修复失败。请确认“筛图神器.app”位于“应用程序”文件夹，并且当前账户有修改权限。"
        exit 1
    fi
fi

if ! /usr/bin/codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    show_message "签名验证仍未通过，请重新复制 App 后再试。"
    exit 1
fi

show_message "修复完成，筛图神器即将打开。"
/usr/bin/open "$APP_PATH"
