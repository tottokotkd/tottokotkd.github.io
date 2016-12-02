---
title: swift buildで渡すオプションをいちいち書きたくないのでcmakeする
date: 2016-11-22 22:33:03
tags:
---

いまサーバーサイドSwiftが盛り上がっています。まだ派手に燃えてはいませんが、確実に火がついています。だいたいXamarin勉強会の翌日くらい燃えてます。

そういう次第でswiftの話です。毎度毎度 `swift build -Xswiftc -I/usr/local/include/mysql -Xlinker -L/usr/local/lib
` とか書きたくない人は幸せになれるかもしれないです。

## CMakeFiles.txtを書くべし

まずこういうやつ書いてください。ビルドコマンドのオプションを適宜いい感じにしましょう。

```cmake
cmake_minimum_required(VERSION 3.6)
project(MariaDbTaler)

set(SOURCE_FILES
        Sources/MariaDbDriver.swift
        Package.swift)

set(SWIFT_COMMAND
        swift build
        -Xlinker -L/usr/local/lib
        -Xcc -I/usr/local/include
        -Xswiftc -lmysqlclient)

add_custom_target(MariaDbTaler
        COMMAND ${SWIFT_COMMAND}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        SOURCES ${SOURCE_FILES})
```

なお試してませんが明らかに`SOURCE_FILES`は書かなくてよい気がいたします。

## `cmake .`すべし

[人類なら`out-of-source`ビルドしなさい](http://qiita.com/osamu0329/items/7de2b190df3cfb4ad0ca)という話もありますが、最初はまあいいです。1回実行してゴミファイルが大量に出来てから後悔しても遅くないです。

## `make XXXXXX` すべし

上の例だと`make MariaDbTaler`ですね。プロジェクト名を渡してやります。そうするとあらかじめ設定してあるコマンドが走るのです。

## 別にCMakeいらなくね？

いらないです。CMake経由しても特にいいことないしシェルスクリプト書けばいいじゃん。なんだよこれ！

ところが、みんな大好きJetBrains謹製IDEであるCLionくんが "[CLion relies on CMake project model, so you need to start a CMake project for Swift](https://blog.jetbrains.com/clion/2015/12/swift-plugin-for-clion/)" と宣うているのです。正直まだまだCLionのSwiftプラグインはショボくて辛い感じなのですが、CLionを使うならCMakeFiles.txtは嫌でも書かなきゃいけません。そこで一括して書けると考えれば、まあちょっとだけ便利です。

## 余談: -Xswiftc is 何

`swift --help`ってなんか使いにくい気がしてならないんですよね。ヘルプ叩いたらサブコマンドの一覧も出してほしいし… `swift package update`の存在とか分かりにくすぎるし… しかしまあそれはいいです。

`-Xswiftc`のことは`swift build --help`すれば分かります。

```swift
$ swift build --help

OVERVIEW: Build sources into binary products

USAGE: swift build [mode] [options]

MODES:
  -c, --configuration <value>   Build with configuration (debug|release) [default: debug]
  --clean [<mode>]              Delete artifacts (build|dist) [default: build]

OPTIONS:
  -C, --chdir <path>       Change working directory before any other operation
  --build-path <path>      Specify build/cache directory [default: ./.build]
  --color <mode>           Specify color mode (auto|always|never) [default: auto]
  -v, --verbose            Increase verbosity of informational output
  -Xcc <flag>              Pass flag through to all C compiler invocations
  -Xlinker <flag>          Pass flag through to all linker invocations
  -Xswiftc <flag>          Pass flag through to all Swift compiler invocations

NOTE: Use `swift package` to perform other functions on packages
```

`-Xswiftc`は分かったけど`-I/usr/local/include/mysql`が分からないんですけど！という人がいると困るので`swift --help | grep -e -I`します(全文は長い)。

```swift
$ swift --help | grep -e -I

  -I <value>             Add directory to the import search path
```

gccでよく見かける愉快な仲間たちですね。Xcodeを使っていると普段全く意識しないと思いますが、-Iは「ヘッダーファイルをどこで探すか」を指定するオプションです。Xcodeのビルド設定にも`header search paths`とかいう項目がありますよね。アレですアレ。

これはつまり古代C言語の領域に突入しているわけです。`swift build`の挙動がよく分からないという人はC++あたりのコンパイラ・リンカの解説記事を読むといいかもしれないです。

決してコンパイラーではありません、コンパイラです。