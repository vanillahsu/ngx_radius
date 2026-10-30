# test_stream.t
use strict;
use warnings;
use Test::More;
use IO::Socket::INET;

subtest 'test connection and lua execution' => sub {
    my $port = 12345;

    # 1. 測試連線能力 (使用 IO::Socket::INET 代替 Test::Nginx::Socket)
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    );

    ok($socket, "Successfully connected to stream port $port");

    if ($socket) {
        # 2. 測試 Nginx 是否有正確執行 Lua 並回傳預期的訊息
        # 我們發送一個空的內容，等待 Nginx 回傳
        print $socket "PING";
        local $/ = undef; # 設定讀取模式，直到遇到 EOF
        my $response = <$socket>;

        # 驗證回傳內容
        like($response, qr/Dictionary loaded/, "Nginx Lua logic responded correctly");

        $socket->close;
    }
};

done_testing();
