FROM openresty/openresty:alpine

# 1. 安裝 Perl, lua 與編譯工具
RUN apk add --no-cache perl lua make gcc musl-dev perl-dev wget

# 2. 手動安裝 cpanm
RUN wget https://cpanmin.us -O cpanm && chmod +x cpanm && ./cpanm Test::Nginx

WORKDIR /app

# 4. 複製所有檔案 (包含 nginx.conf, dictionary.lua 等)
COPY . .

# 5. 建立啟動腳本 (優化版本，包含 PID 管理與結果輸出)
RUN cat <<'EOF' > run_test.sh
#!/bin/sh
APP_DIR=$(pwd)

# 設定 LUA_PATH 以確保 Nginx 能找到當前目錄下的 lua 檔案
export LUA_PATH="$APP_DIR/?.lua;$APP_DIR//*.lua;;"

echo "正在啟動 Nginx (使用 $APP_DIR/nginx.conf)..."

# 在背景啟動 Nginx
nginx -c "$APP_DIR/nginx.conf" -g "daemon off;" &
NGINX_PID=$!

# 等待 Nginx 啟動完成
echo "等待 Nginx 啟動..."
sleep 2

echo "正在執行單元測試 (test_tlv.lua)..."
lua5.5 "$APP_DIR/test_tlv.lua"
TLV_RESULT=$?

if [ $TLV_RESULT -ne 0 ]; then
    echo "❌ TLV 單元測試失敗!"
    kill $NGINX_PID
    exit 1
fi

echo "正在執行整合測試 (test_stream.t)..."
# 執行 Perl 測試腳本
perl test_stream.t
TEST_RESULT=$?

echo "正在停止 Nginx (PID: $NGINX_PID)..."
# 停止 Nginx 程序
kill $NGINX_PID

if [ $TEST_RESULT -eq 0 ]; then
    echo "---------------------------------"
    echo "✅ 測試成功!"
    echo "---------------------------------"
    exit 0
else
    echo "---------------------------------"
    echo "❌ 測試失敗!"
    echo "---------------------------------"
    exit 1
fi
EOF

RUN chmod +x run_test.sh

CMD ["/app/run_test.sh"]
