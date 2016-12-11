---
title: Swift + Kitura + MySQLで頑張っている件
date: 2016-12-02 12:33:13
permalink: 1
tags:
- Swift
- Kitura
- MariaDB
- Sterntaler
---

このコードをコピペすればswiftでmysqlサーバー叩いてJSON垂れ流せるぞ！ (実際に試したのはMariaDBだけど)

まずパッケージね。試してないけどLinuxでも動く気がする。

```swift
import PackageDescription

let package = Package(
    name: "nwsns",
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 1, minor: 2),
        .Package(url: "https://github.com/tottokotkd/MariaDbTaler.git", majorVersion: 0, minor: 1)
    ])
```

そしてサーバー立てる。コードは超簡単だから説明不要ですねえ。

```swift
import Foundation
import Sterntaler
import MariaDbTaler
import Kitura
import SwiftyJSON

// Create a new router
let router = Router()
let pool = MariaDB.get(host: "127.0.0.1", user: "root", password: "pass", database: "fosdb")
let columns = (Columns.int("id"), Columns.string("name"), NullableColumns.date("day"))

// Handle HTTP GET requests to /
router.get("/") { request, response, next in
    let data = pool.execute(sql: "SELECT id, name, day FROM test")
        .map{$0.read(tuple: columns)}
        .map{["id": $0.0, "name": $0.1, "day": $0.2?.description ?? "null"]}
    try! response.status(.OK).send(json: JSON(data)).end()
    next()
}

// Add an HTTP server and connect it to the router
Kitura.addHTTPServer(onPort: 8090, with: router)

// Start the Kitura runloop (this call never returns)
Kitura.run()
```

Sterntaler / MariaDbTalerとかいうモジュールがMySQL Connector/Cの自作ラッパーです。ホントは劣化Slickみたいなすごいやつ作りたかったけど当然無理なので妥協しました。SQLインジェクション対策すらない時点で100%ダメなのですけど、でもなんだか既存のコードもしっくり来なくて… 

ちなみにプールとか言ってますが勿論ウソです。毎回つないでます。


これを動かす場合、`brew install mariadb`でMariaDBを入れて、それっぽいデータベースとテーブル作って、`swift build -Xlinker -L/usr/local/lib -Xcc -I/usr/local/include -Xswiftc -lmysqlclient`でビルドすれば動く気がします。もちろんKituraの依存ライブラリーも入れましょう。

ちなみに、いま世間にいくつかあるSwift系mysqlライブラリーにはOpenSSLが入っていないとビルドできないものがあるみたいです。ところがOpenSSLをbrewでインストールするとリンク段階で失敗することがあるので、その場合ビルドするときには`-Xcc -I/usr/local/opt/openssl/include -Xlinker -L/usr/local/opt/openssl/lib`とか指定するといいです。たぶん。

（それらはGPLに静的リンクしているような気がするけど調べてません）

この方向で何かちょっと動くものを作れるか頑張ってます。しかし実際どうなるかはわかんない。