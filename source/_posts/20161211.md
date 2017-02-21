---
title: Kotlin + AWS Lambda + API GatewayでServerlessできちゃうラッパー公開したのでDynamoDBとか使っちゃう
permalink: 1
date: 2016-12-11 12:36:08
tags:
- Kotlin
- AWS
---

タイトルの通りです。[githubに置いてある](https://github.com/tottokotkd/GatewayHandler)し、[Bintray経由でjcenterにもある](https://bintray.com/bintray/jcenter?filterByPkgName=GatewayHandler)ので使えます。この公開ルートは今回初めてやってみましたが、なかなか便利ですね。

もちろん公開するだけならgithubページでもイケるんですけど、その作業が手間だったり、IntelliJくんがキャッシュ持つ段階でエラー吐いたり、面倒なのでBintrayです。今はあんまりそこを頑張りたくなかった、仕方なかった。

githubの方に書いてあるんですけど、コードでいうとこんな感じ。

```kotlin
package hello

import com.amazonaws.regions.Regions
import com.amazonaws.services.dynamodbv2.document.DynamoDB
import com.amazonaws.services.dynamodbv2.document.Item
import com.amazonaws.services.lambda.runtime.Context
import com.tottokotkd.aws.gateway.core.*
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.properties.Delegates

class SaveRequest {
    lateinit var user: String
    lateinit var url: String
    var rate: Int by Delegates.notNull()
    lateinit var timestamp: String
}

class SaveHandler: DataHandler<SaveRequest, Any> {
    override fun handleRequest(input: SaveRequest, context: Context): ResponseData<Any> {

        val timestamp = try {
            ZonedDateTime.parse(input.timestamp, DateTimeFormatter.ISO_DATE_TIME)
        } catch (e: Exception) {
            return ResponseData(mapOf("status" to "error", "desc" to "date time parsing failed."), StatusCode.BadRequest)
        }

        val dynamoDB = DynamoDB(Regions.US_EAST_1)
        val t = dynamoDB.getTable("pages")
        val item = Item.fromMap(mapOf("user" to input.user, "url" to input.url, "rate" to input.rate, "epoch" to timestamp.toEpochSecond(), "timezone" to timestamp.offset.totalSeconds))
        val result = t.putItem(item)

        return ResponseData(mapOf("status" to "success", "input" to input))
    }
}
```

`SaveHandler`がリクエストハンドラーで、`SaveRequest`がリクエストに期待される内容ですね。言うまでもないか。

API Gateway経由なのでJSONを渡されそうなものですが、実際はアマゾンがPOJOに突っ込んだうえで渡してくれます。Serverlessの設定として書くべきことも特になくて、本当にこのままLambdaにデプロイすれば面倒をみてくれます。DynamoDBもIAMさえ弄ればコードは1行で終わり。

たったこれだけで (金さえ払えば) 無敵のスケーラビリティが手に入っちゃう。スゴイ！

ただしアマゾン様といえどもdata classのコンストラクタを使うような器用な芸当は当然やれないので、`SaveRequest`はプロパティ全てvarのクラスになっています。もっともここは`val hoge: String by Delegates.notNull()` の方がいいような気もするし、Web APIなんだから`String?`の方がかえってロジカルに書きやすいような気もするし、その辺りは僕もまだ深く考えてません。

そこまでkotlinやAWSの挙動に詳しくないという事情もある。

それはともかく戻り値が`Any`になっていて許せん！という人もいると思いますが、これはmapOfで手軽に返したかったのです。データクラスとか指定すればちゃんと型安全で動きます (たぶん)。

まあこの辺りは趣味の問題でもあり、生産性を上げるために工夫のしどころでもあります。`ResponseData`を使わず自前で実装する方がいいかもですね、ステータスコードは引数じゃなくて型に結びつけるとか。あるいはハンドラーの方にヘルパーをバシバシ生やすとか… 

その辺は今後ちょっと便利になったらいいかなあ。いいアイデアあったらPRください。



で、コードはもう特に書くことないので思い出をつらつらと。

## API Gateway -> Lambda -> Error!

`sls invoke -f hello` が動くぞ！やったー！などと隙を見せたエンジニアを強襲するAWS！

> Malformed Lambda proxy response

lambdaとしては呼べるけどcurlすると落ちる。

Serverless使って一番つらかったのはコレ。Kotlin + Serverless + API Gatewayなんて実際に使っているケースがほぼ見つからない上に、数ヶ月前の記事で「動きました！簡単」とか書いてあるコードがもう動かない。嘘だゾ、全然簡単じゃないゾ。


ということで頑張って検索して探したのがコレ。~~人柱サンキュー！~~

{% blockquote kyl191 https://forums.aws.amazon.com/thread.jspa?threadID=239688 AWS Developer Forums: Lambda Proxy Expectations %}
Ok, I found some documentation which says it expects statusCode, body and headers in a dict.
{% endblockquote %}

何でこんな状態なのか、ちょっと意味が分からないんですけど、API Gateway (Lambda Proxy) から呼ばれるLambdaは**戻り値の型はどうでもいいしインターフェイスとかないけど、statusCode body headersという3つの値を持っていないと実行時エラーになる**という凡そJavaとは思われない動的な仕組みになっているみたいです。

つまり、`sls invoke -f hello`の結果として

```json
{"hage": ["ok", "cool", "amazing"]}
```

みたいな結果が見えている場合はダメです。

Lambdaとしては動いているのですが、Gateway経由で呼びたいなら以下の内容でなければいけません。


```json
{
    "body": {
        "hage": ["ok", "cool", "amazing"]
    },
    "headers": {},
    "statusCode": 400
}
```

このフォーマットを守らなければ、Lambda ProxyモードのAPI Gatewayは有効な結果として受け付けてくれないのです。理屈が分かってしまえば納得できますが、この落とし穴だけは本当にひどい罠だと思います。

一旦Lambda側からJSONを出力した上で、それを改めてGateway側がチェックするんでしょうか？ 色々と想像してますが謎です。

ちなみにデータのJSON化はあっちがJacksonでやってくれるので、上記のようなプロパティを持つPOJOを投げればいいみたいです。kotlinならdata classですね。あと試していませんがmapでも大丈夫かなと。

ただまあ、そこを自由にしても特に利点がなさそうなうえ、誰の目にも明らかにバグの温床でしかありません。今回のラッパーでは3つのプロパティを明示的に要求するインターフェイスを作っておきました。そもそも本来こういう仕様になってなきゃJavaコードとしておかしいと思うんですけど、それはそれで公式SDKとしては狭すぎる感じもありますからね… まあ気持ちはわかります。クソですけど。

Lambdaプロキシ自体が割と新しい機能であることも考えると仕方ない、AWSはこういうものなのだ… と割り切りましょう。

## 2つの型パラメータを持つジェネリッククラスでないとエラーになる

もうエラーログが手元にないんですが、リクエストハンドラーとして型パラメータ1つのクラスを作ってみたら「型パラメータは2つないと困るんだよなァ！」みたいな激おこメッセージを飛ばしてきました。これまたちょっと意味が分からないんですけど、JSONをリクエストPOJOに変換するときに型パラメータを使おうとしているのかな？ とにかくダメなものはダメらしいです。

それにしたって型パラメータ2つじゃないとダメっておかしくねえか？設計どうなってんの？という気もしますが仕方ない、AWSはこういうものなのだ… と割り切りましょう。

## Internal Server Error
API Gatewayを通過して結果が戻ってくるまでの間にエラーが発生するとInternal Server Errorです。例えば「Lambda処理内でリクエストパラメータを参照したらnull例外で落ちた」とかいう場合、それはInternal Server Errorであり、Gatewayのデフォルト処理が走って超ダサいJSONを投げ返します。

サーバー内部でエラーが発生するなら、API Gatewayの視点からは全てInternal Server Errorなのです。まあそりゃ当然の挙動なんですけど、それはAPIを書く側からするとBadRequestだし、そもそも勝手にダサいJSONを流されるのも困ります。

ということでつまり、ハンドラ全体をtryで囲わないと不安だし、リクエスト内容の処理もちゃんと書かないといけません。当たり前の話とはいえ若干ちょっと面倒そう…

その辺りをうまく集約できるインターフェイスとか作らないと大変そうですね。まあもちろん「ステータスコードさえ取れるなら大丈夫、後はYAGNI」という考え方もあると思います。その辺りの線引きはちょっと難しそう。

## ということで

なんか動くものは作れそうだし頑張る。