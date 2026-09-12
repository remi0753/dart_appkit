# Dart AppKit — 汎用 macOS GUI ロードマップ

## 目的

このロードマップの目的は、現在のターミナル向け基盤を中心とした
`dart_appkit` と `dart_macos_runtime` を、Dartから一般的なmacOS GUI
アプリケーションを構築できる基盤へ段階的に拡張することである。

現在の実装は、AppKitメインスレッド上でDartを安全に実行し、1枚の専用
ビューへ低水準入力を届け、terminal専用のIME入力と読み取り専用accessibilityを
提供する用途には適している。一方、フォーム、設定画面、テキストエディタ、
ファイルブラウザ、データ一覧などを実装するには、ビュー階層、レイアウト、
標準コントロール、汎用の編集可能テキスト／semantics、macOSサービスとの統合が
不足している。

本ロードマップでは、macOSネイティブのAppKitコントロールを基本とし、特殊な
描画面だけをMetalや独自レンダラーで実装するハイブリッド方式を採用する。
Flutter相当のクロスプラットフォームWidget／レンダリングエンジンを
`dart_appkit` 本体に構築することは、現在の主要目標には含めない。

## 維持するアーキテクチャ上の条件

- AppKitとDartのUIルートはmacOSのプロセスメインスレッド上で動作する。
- ネイティブイベントはDartへ非同期に配送し、delegateからDartへ同期再入しない。
- Dartメッセージ処理はAppKit run loopを占有しないよう、回数と時間で制限する。
- ネイティブオブジェクトは世代付きハンドル、明示的な所有権、main-thread release、
  安全なfinalizer releaseを維持する。
- Dart SDK／Engineは公開された公式ソースをそのまま使用し、patch、fork、private
  API、private bootstrap実装に依存しない。
- 現在のEngine契約では、UIプロセス内はprocess-lifetimeのroot isolateを1つだけ
  サポートする。CPU負荷の高い処理は必要に応じて外部Dart helperへ分離する。
- 汎用ホストには基礎契約だけを置き、WebView、Metal renderer、PTYなどの選択的・
  製品固有機能はnative capability／native asset packageとして分離する。
- `dart_appkit` はAppKitのmechanism、ownership、lifecycle、hard safety boundだけを所有する。
  application固有の文言、色／装飾、layout、URL scheme allowlist、close／quit／復元判断などの
  product policyは、型付きparameterまたはapplication側のstate／callbackとして与える。
- library defaultは安全かつ保守的に保ちながら、platform上妥当な選択肢をapplicationが
  明示的に選べるようにする。特定consumerで測定した値を汎用defaultへ固定しない。
- C ABI、イベントprotocol、capability ABIはversionedかつ後方互換な形で拡張する。
- IME、キーボード操作、アクセシビリティは出荷直前の追加項目ではなく、
  コントロール基盤と同時に設計・検証する。

## 作業ルール

1. 同時に進行する主要ロードマップ項目は原則1つとする。
2. 調査結果、設計判断、検証コマンド、完了根拠は `docs/WORKLOG.md` に記録する。
3. 完了条件を満たし、既存regressionを通過した項目だけを `[x]` に変更する。
4. 公開ABIを変更する項目では、旧クライアント、旧event protocol、JIT/AOTの
   compatibilityを確認する。
5. 各項目でDart unit test、native contract test、必要なGUI integration testを
   同時に追加し、テスト整備だけを最後まで先送りしない。

## 現在位置

- 旧MVPロードマップの **T0〜T14は完了**している。
- 旧タスクIDは `docs/WORKLOG.md` と `docs/VERIFICATION.md` の履歴参照用として
  維持し、今後のタスクには再利用しない。
- Terminal rendererトラックの次の中心作業は、grid／cell model、atlas allocation、
  frame構築、cursor／selection、damage trackingに加え、実screen stateからのcaret geometry／
  accessibility snapshot公開、text-input eventのterminal処理、owner側の再試行／障害回復を
  既存pipelineへ統合することである。
- 現在の検証済み基準は、arm64上のDeveloper JIT／Release AOT、Timer動作、
  ウィンドウ・メニュー・入力イベント、close/terminate応答、native handle解放、
  event protocol v5のprecision scroll、v6のouter-frame／native-fullscreen state、
  v7のapplication effective-appearance、
  native window tab、2-child SplitView、first responder設定、window presentation metadata、
  boundedなplain-text pasteboard read、allowlist付き外部URL起動、capability loading、
  PTY ABI v5のprocess snapshot／consumer-configured read scheduling、process exit 0に加え、
  terminal rendererのC/C++ ABI、
  CoreText font／shape／top-down raster、Metal readback／submission、atlas reset、failure state、
  renderer metrics、Dart facade、bounded `NSTextInputClient` event、candidate geometry、
  deterministic input-source matrix、読み取り専用AppKit accessibilityである。
  Terminal renderer capability ABIはversion 11である。

## 実装済みの基盤

以下は旧T0〜T14と、その後追加された実装を機能別に再整理したものである。
旧T0〜T14の詳細な時系列と判断理由は `docs/WORKLOG.md`、検証結果は
`docs/VERIFICATION.md` を正とし、その後の実装状況は現行コード、各packageのtest、
関連するworklogを根拠とする。

### [x] B0 — Dart／AppKitホストとイベントループ

- `NSApplication` とAppKit run loopをプロセスの外側のイベントループとして実装。
- AppKitメインスレッド上で公式Dart Engineのroot isolateを起動。
- Dart messageを1 turnあたりの件数・時間で制限するmessage pumpを実装。
- `Future`、microtask、periodic `Timer` とAppKitイベントが共存することを検証。
- 起動失敗、Dart fatal error、終了code、bridge shutdownの順序を実装。
- 公開 `dart_api.h` のみを使う代替hostをJIT/AOTで評価し、不採用理由を記録。

### [x] B1 — C ABI、Dart FFI、ネイティブ所有権

- status code、thread-local error、UTF-8文字列、opaque handleによるplain-C ABIを実装。
- slotとgenerationを含むnative object registryとstale-handle検出を実装。
- main-thread-only同期release、任意threadからの非同期release、
  `NativeFinalizer`、shutdown時の残存handle cleanupを実装。
- ABI versionとevent protocol versionを独立して管理。
- fake native bindingsを用いたDart側のAPI／error／lifecycle testを実装。

### [x] B2 — Application、Window、Viewの最小API

- `AppKitApplication.attach()`、application active、reopen、terminate requestと応答を実装。
- 固定styleのWindow生成、表示、title変更、programmatic close、user close request、
  close deferralを実装。
- resize、focus、visibility、occlusion、backing scale、接続screenの状態イベントを実装。
- Window生成／変更で一貫したouter frameを扱い、負のmulti-screen座標を含む変更／観測、
  非同期native fullscreen要求と完了イベント、transition中のwindowed-frame保全を実装。
- Window同士をnative tab groupへ追加／分離／選択するAPIと、既存content hierarchy内の
  `View` をfirst responderへ設定するAPIを実装。
- boundedなabsolute `representedFilePath` とsRGB `WindowTabColor` により、標準proxy icon／
  path menuとnative-tab accessory markerを設定／解除するpresentation metadataを実装。
- 汎用 `View`、表示専用の簡易 `TextView`、Windowへの単一content view設定を実装し、
  focus／autoresize／font／padding／colorをimmutable creation configurationへ分離。
- axis、2つのordered child、fraction、両childのminimum extent、equalize、one-child zoomを
  持ち、nested compositionできるnative `TwoPaneSplitView` helperを実装。旧 `SplitView` 名は
  deprecated aliasとして互換維持する。
- dependencyが登録したnative `NSView` を `View.custom()` で生成できる仕組みを実装。
- Dart/native双方で再検証するdeny-by-defaultな `AllowedExternalUrl` と、application-ownedな
  immutable scheme policyで登録済みmacOS handlerを開く `AppKitApplication.openExternalUrl` を実装。

### [x] B3 — 入力イベントとキー配送

- Windowを発生元とするmouse down/up/move/dragイベントを実装。
- key down/up、key code、modifier、repeat、charactersをDartへ配送。
- 通常のAppKit responder chainも通す `dartAndAppKit`、メニューshortcutを優先した後で
  Dartだけへ配送する `dartOnly`、残りをfirst-responder／input-client chainだけへ配送する
  `appKitOnly` をWindow単位で選択可能にした。
- event protocol v5に、flipped content座標、pixel精度delta、通常／momentum phase、
  device inversion、modifierを持つWindow発生元の `AppKitScrollEvent` を追加。
- input、window、application eventをversion 1〜7でstrict decode／routeし、旧protocolでは
  新しいeventを安全に除外する仕組みを実装。

### [x] B4 — MenuとプレーンテキストPasteboard

- main menu、submenu、separator、shortcut、enabled state、menu action eventを実装。
- applicationとMenuItem固有streamへのaction routingを実装。
- general pasteboardのplain text read/write/clear/change countを実装。
- Unicode、空文字、値なし、NULを含む文字列、native failureを検証。
- plain text readを64 MiB UTF-8に制限し、超過時はpartial dataを返さず型付きstatusで失敗する
  Dart/native境界を実装。

### [x] B5 — Native capability／native asset基盤

- versioned native-extension service tableと、名前付き `NSView` factory登録を実装。
- manifestに宣言したcapability dylibのbuild hook、staging、ABI検証、初期化、
  process-lifetime image retentionを実装。
- Objective-C pointerをapplication Dartへ公開せず、生成したviewを通常の
  generation-checked handleとして管理。
- providerが同じprovider製custom Viewに対して1つのopaqueな同期operationを登録できる、
  size-prefixed service-table拡張を実装。旧table prefixとの互換性を維持している。
- `View.performCustomOperation(Uint8List)` を実装。main thread、View generation、provider一致を
  host側で検証し、payloadを同期呼び出し中だけ貸し出す。Objective-C pointerやAppKitの
  registry handleはDartへ公開しない。
- AppKitへ登録しない独立native assetのbuild／staging経路も実装。

### [x] B6 — 再利用可能なmacOS application runtime

- `dart_macos_runtime` とstrict JSON application manifestを実装。
- 同じDart `main(List<String>)` からDeveloper JIT／Release AOT bundleを生成。
- application identity、minimum macOS version、resources、native assets、
  native capabilities、diagnosticsの宣言と検証を実装。
- application-owned Dart helperを自己完結実行ファイルとして
  `Contents/Helpers` にbuild／stageする機能を実装。
- bundle resource、Framework、helperの安全なpath lookupを実装。
- boundedなscripting definitionのDTD検証／resource staging、標準plist宣言、
  build manifest監査をoptional manifest境界として実装。
- privacy-bounded lifecycle diagnosticsとad-hoc signingを実装。

### [x] B7 — ターミナル向け独立機能

- `dart_terminal_renderer_macos` に、paused／on-demand／framebuffer-onlyの
  flipped `MTKView` とnative capability境界を実装。
- CoreText font catalogをgeneration-owned resourceとして実装。regular／bold／italic／
  bold-italic、明示的なsynthetic style policy、CJK／color emoji fallback、cell／baseline／
  underline／strike metricsを扱える。
- complete text unitをrun／face／glyphへ変換するbounded shaping ABIとDart APIを実装。
  UTF-16 cluster、位置、advance、fallback／RTL／missing glyph、ligature featureを保持し、
  entry数とbyte数を制限したDart-owned LRU cacheを提供する。
- backing scaleに応じてunique glyph setを一括rasterizeするAPIを実装。top-down alpha8 maskと
  straight RGBA8 color glyph、baseline-relative bearingをcopy-owned resultとして返す。
- Core Graphicsの座標変換後にglyph rowを二重反転しないtop-down contractへ修正し、非対称な
  glyphを2xでrasterizeして上下方向を検出するregression testを追加。
- build時にMetal shaderをcompileしてdylibへ埋め込み、bounded resource set、alpha／color
  texture array、atlas dirty-rectangle upload、generation検証、layer順を持つpacked frame、
  deterministic RGBA readbackを実装。
- active frameがない時にatlas generationを原子的に進め、全texture sliceとpage generationを
  clearする `resetAtlas` を実装。dummy glyphを作らず空または全再構築を開始できる。
- rendererとcustom `MTKView` の安全なbinding、3つの固定slotによるproduction submission、
  newest-ready選択、即時backpressure、drop／GPU完了後のretirement watermarkを実装。
- device、embedded shader、function、pipeline、resource allocationの生成失敗と、command
  encoding／execution、device lostのruntime faultを型付き状態として公開。runtime faultは
  そのrenderer instanceをterminal fault状態にして後続frame admissionを停止する。
- drawableを取得できない場合はfaultにせずREADY frameを保持し、visibility／resume ownerが
  `requestPresentation` で次の有効な時点に再描画を要求できるようにした。
- submission／completion／stale drop／backpressure／drawable miss／command failureに加え、
  成功したGPU処理時間のsample数・合計・最大値と、受理したatlas uploadの件数・byte数を
  saturating counterとして `TerminalMetalRendererState` に実装。
- `TerminalMetalRenderer`、config、atlas upload、frame encoder、submission result、stateを
  型付きDart facadeとして実装し、atlas reset、presentation retry、failure分類、metrics、
  明示dispose、NativeFinalizer fallbackを提供する。
- `TerminalMetalView` を `NSTextInputClient` として実装し、raw key、preedit、commit、cancel、
  overflowをcopy-ownedなbounded queueから非同期通知する `TerminalTextInputClient` を追加。
  text fieldを64 KiB UTF-8、queueを256 event／1 MiBに制限し、隣接preeditのcoalescing、
  generation検証、明示detachを実装した。
- IME candidate queryがDartへ同期再入せず最新のnative copyを使える、generation付き
  `publishCaretRect` を実装。terminal byte encodingとcomposition policyはDart ownerに残す。
- 同じViewを読み取り専用AppKit accessibility text areaとして実装し、visible text、UTF-16
  physical line／terminal-column境界、selection、cursor、cell geometry、logical content originを含むboundedな
  `TerminalAccessibilityViewSnapshot` をDartから原子的に公開できるようにした。
- accessibility queryはnative snapshotだけを参照し、range／line／point／screen frameを
  提供する。pointはpadding／grid外を拒否し、range frameはcontent originを一度だけ加える。
  値またはgeometryが変わった場合だけnotificationを発行し、first responder時のfocused stateも
  AppKit selector acceptanceで検証した。
- `dart_pty_macos` に、AppKit非依存のPTY生成、非同期read/write、bounded queue、
  backpressure、resize、signal、graceful/forced close、exit/reapを実装。
- 親processのstdinが閉じた状態でもexec-error pipeをstandard descriptorから退避し、childの
  controlling-terminal stdinを誤ってclose／aliasしないspawn処理を実装。
- PTY ABI v5に、child PID、owning／foreground process group、個別syscall error、exit stateだけを
  同一callで返すcontent-free `PtyProcessSnapshot` を追加。process名、argv、environment、cwd、
  terminal byteをlibrary側で解釈せず、close／quit判断をconsumerへ残した。
- `PtyCommand.readBatchBytes` で64 KiB以下のdelivery boundをconsumerが選択でき、同期stream
  consumerの処理完了後にordered ACKすることで、queued callbackではなく受理済みworkへ
  read creditを対応付ける仕組みを実装。
- `readBatchesPerEventLoopTurn` の0〜8をapplicationが選べるようにし、0は従来動作を保持、
  非zero時は同時に1 batchだけを未ACKとして保持して指定回数ごとに次のDart event turnへ譲る。
  EOF後もoutstanding batchのACK完了までexit／destroyを進めない。
- terminal-specific protocol、renderer、recovery policyを汎用hostから分離。

注意: 上記は描画、text input、accessibilityの低水準基盤である。terminal grid／cell model、
atlasのallocation／packing／eviction、terminal stateからframeへの変換、cursor／selectionの
高水準挙動、damage tracking、実sessionへのtext-input／caret／accessibility snapshot接続は
まだ未実装であり、X0に残る。

### [x] B8 — Build、検証、サンプル

- 公式Dart SDK revisionの検証とEngine build bootstrapを実装。
- `dart_appkit:run`、manifest-driven builder、bundle assembly、stdio／argument／
  exit-code forwardingを実装。
- hello-windowのJIT/AOT GUI smoke、native bridge test、C/C++ header test、
  FFI smoke、Dart analysis/unit testを実装。
- native handle churn、wrong-thread、stale event、event encoding、capability lifetime、
  PTY integrationを含むregression suiteを実装。
- terminal rendererについて、C/C++ ABI layout check、native resource／generation／bound check、
  strict packed-buffer decoder、mixed-script shaping、1x／2x glyph raster、atlas generation、
  Metal pixel readback、triple-buffer／backpressure、typed Dart facadeのtestを実装。
- empty／populated atlas reset、stale／active-slot rejection、生成時failure分類、drawable miss、
  明示的presentation retry、command encoding／completion fault、fault後のadmission停止、
  GPU timing／atlas upload metricsをdeterministic fault injection込みで検証。
- event protocol v5のscrollとv6のframe／fullscreen encoder／strict Dart decoder／
  旧protocol filtering、native tab／SplitView／first responder、window metadata、64 MiB
  pasteboard read上限、外部URLのDart/native二重validationとLaunch Services recorderを検証。
- test専用libraryからnativeのdeferred termination state machineを起動するhookを追加し、
  production APIへ公開せずoperation-ID replyとrefusalのfailure atomicityを実processで検証。
- PTYについてclosed parent stdin、foreground process snapshot、64 KiB default／consumer指定batch、
  consumer-completed ACK、configurable event-turn budget、EOF時outstanding ownershipを検証。
- terminal text inputについて、staged raw／preedit／commit／cancel、candidate geometry更新、
  overflow／bound、ASCII・CJK・emoji・modifier・repeatのdeterministic input-source matrixを検証。
- terminal accessibility snapshotのDart/native二重validation、stale／malformed／unsupported version拒否、
  zero/nonzero content origin、padding/grid外hit拒否、AppKit selector／range geometry／notification／
  first-responder focusを文字列をDartへ戻さず検証。

### [ ] 汎用repositoryの製品所有権是正

達成目標: `dart_appkit` と `dart_macos_runtime` を汎用AppKit/runtime機構だけに限定し、
製品package、製品語彙、表示policy、検証所有権をconsumer repositoryへ移す。

- [x] tracked package／build target／汎用code内semantic leakの全件inventoryを作成し、
  [`docs/WORKLOG.md`](docs/WORKLOG.md) とconsumer側task memoに移設順と完了条件を記録する。
- [x] PTY native asset packageと検証所有権をconsumerへ移す。
- [x] renderer capability packageと検証所有権をconsumerへ移す。
- [x] AppleScript capability packageと検証所有権をconsumerへ移す。
- [x] App Intents capability packageと検証所有権をconsumerへ移す。
- [x] folder Servicesのtab/window語彙を汎用actionへ置換し、consumerから意味を注入する。
- [ ] Secure Input固有表示をboundedな汎用badgeへ置換し、consumerから文言を注入する。
- [ ] generic test fixture、現行文書、Makefileを是正し、再混入を拒否するsource auditを追加する。
- [ ] exact full gateとconsumerのDeveloper JIT／Release AOT受け入れ後に親項目を完了する。

## 未実装ロードマップ

主要な依存順は次のとおりとする。

- **G0 → G1 → G2** を、すべての汎用GUI機能の共通土台とする。
- **G3とG4** はG2の後に並行して進められる。
- **G5、G6、G7** はlayout／event基盤を利用し、相互に統合しながら完成させる。
- **G8〜G13** は必要な製品use caseに応じて並行可能だが、共通commandやeventを
  個別実装し直さない。
- **G14** はG1から各項目と並行して拡張し、G13までの公開surfaceを覆った時点で
  完了とする。
- **G15、G16** は早期に必要なdiagnostics／manifest項目を前倒しできるが、正式な
  完了は汎用GUI APIが安定した後とする。
- **G1〜G7、G9〜G12、G14、G15、X0は部分実装済み**である。
  チェックボックスは各項目の完了条件を
  すべて満たした場合だけ `[x]` にする。

### [ ] G0 — 汎用GUIの公開契約と境界の確定

達成目標: 後続のGUI機能を互換性のある形で追加できる、最小の公開モデルを確定する。

汎用性監査の是正順序:

- [x] Runnerのactivation／launch activation／last-window close／reopen policyを
  `RunnerConfiguration` とmanifestから選択可能にする。
- [x] 固定window styleを安全な互換defaultを持つ `WindowConfiguration` へ移す。
- [x] 固定8×8円形のtab color accessoryを汎用またはparameterizedなpresentationへ移す。
- [x] external URLのscheme allowlistとscheme別条件をimmutable application policyへ移す。
- [x] 現在のSplitViewを汎用化するか、明示的な2-pane helperとして境界を定める。
- [x] 基底Viewと簡易TextViewのfocus／autoresize／font／padding／colorをparameter化する。
- [x] Menu auto-enableとmessage-pump budgetをhard upper bound内で構成可能にする。
- [x] bounded user notification送信／取消とDock badge更新を、product policyを持たない
  application mechanismとして追加する。

実装内容:

- AppKit native-control中心のハイブリッド方式を正式な対象モデルとして定義する。
- `dart_appkit`、`dart_macos_runtime`、optional capability package、applicationの
  責任境界を確定する。
- View、Control、event、layout、semantics、native capability instanceの公開概念と
  versioning方針を定義する。
- 現在の公開API／native bridgeを、platform invariant、hard safety bound、library default、
  application policyに分類し、後二者を混同して固定しているAPIをparameter化、汎用化、
  capability分離、または互換性を保った非推奨化の対象として整理する。
- 固定のwindow style、基底 `DaView` のfocus／autoresize、`TextView` のfont／padding／color、
  2-child split helperのdivider／collapse、native-tab marker、external URL scheme allowlistを
  最初の汎用性監査対象とする。
- 設定画面、テキスト入力画面、一覧画面、custom drawing画面を代表use caseとして、
  後続milestoneの受け入れ条件を定める。
- 既存APIとABIを維持する範囲、追加API、非推奨化が必要なAPIを整理する。

完了条件:

- 後続G1〜G16が依存できる公開境界と互換性ルールが文書化されている。
- 少なくとも性質の異なる2つのapplicationで同じcore APIを利用し、一方の見た目、layout、
  workflow、安全policyが他方のdefaultや制約へ混入しないことをconformance reviewで確認する。
- 既存hello-window、terminal capability、JIT/AOT runtimeを壊さない移行方針がある。

### [ ] G1 — 対話的native capability instance

達成目標: 外部packageが、複数の対話的native Viewを型付きDart APIとして安全に
提供できるようにする。

進捗: **部分実装**。

実装済み:

- size-prefixed extension service tableへ、provider単位のopaqueな同期custom View operationを
  後方互換に追加した。
- hostがmain thread、generation-checked View handle、生成providerの一致を確認してから、
  callbackの間だけnative Viewとpayloadを貸し出すfail-closedな経路を実装した。
- Dart側にcopy-in型の `View.performCustomOperation(Uint8List)` を追加し、terminal packageの
  `bindToView` でprovider固有の型付き操作へ包めることを実証した。

未実装:

- 現在のゼロ引数View factoryを拡張し、生成設定を渡せるversioned capability ABIを
  追加する。
- custom operationは一方向の同期payloadに限られるため、capability instance共通の
  identity、ownership、dispose、非同期処理、cancellation、backpressure契約を追加する。
- instance単位のproperty update、typed command、result／state query、event deliveryの
  共通経路を追加する。
- capability eventにprovider namespace、instance source、protocol versionを持たせる。
- 外部packageがprivate APIなしで型付きView wrapperを提供できる公開Dart拡張APIと、
  provider／instance lifecycleを再現するtest backendを追加する。

完了条件:

- 1つのcapabilityから複数instanceを生成し、個別に状態更新・event受信・破棄できる。
- old service-table clientと既存 `View.custom()` がそのまま動作する。

### [ ] G2 — View階層、geometry、共通property

達成目標: 1つのWindow内に複数のViewを安全に構成できるようにする。

進捗: **部分実装**。`SplitView` 内の限定された2-child hierarchyは構成できるが、
すべての `View` に共通するtree APIはまだない。

実装済み:

- `SplitView.setChildren` で2つの異なる同一application Viewをordered childとして設定し、
  self／重複／循環となるnative hierarchyを拒否する。
- `SplitView` 自身も通常の `View` としてcontent viewまたは別のSplitView childにでき、
  nested treeを構成できる。
- `Window.makeFirstResponder` は、対象がそのWindowのcontent hierarchy内にあることをnative側で
  検証してから設定する。
- package-createdな基底 `View` と簡易 `TextView` は、first-responder可否とwidth／height
  autoresizeをimmutable `ViewConfiguration` で選択できる。custom viewはprovider-ownedとする。

未実装:

- subviewの追加、挿入、削除、並べ替え、reparent、parent/children参照を追加する。
- `Point`、`Size`、`Insets` などの基本geometry型と、frame、bounds、座標変換を追加する。
- hidden、opacity、clip、tooltip、autoresizingなど、View共通propertyを追加する。
- hierarchy attachmentとDart/native handle ownershipを分離し、detach、dispose、
  Window retain時の規則を定める。
- tree mutation中のstale event、二重parent、循環、異なるapplication間のattachを拒否する。

完了条件:

- nested View treeを構築・変更・破棄でき、native/Dart両方で所有関係が一致する。
- Window resize後もchild viewの状態と座標変換が正しく取得できる。

### [ ] G3 — レイアウト基盤

達成目標: Windowサイズやcontentの変化に応じて、一般的なGUIを宣言的に再配置できる
ようにする。

進捗: **部分実装（SplitView専用）**。2-pane layoutだけがnative resizeに追従する。

実装済み:

- `SplitView` にhorizontal／vertical axis、0より大きく1未満のfraction、各childのminimum extent、
  equalize、one-child zoomを実装した。
- native bounds変更とdivider dragに追従して2 childを再配置し、minimum extent内へclampする。

未実装:

- AppKit Auto Layoutを安全に表現するanchor、constraint、priority APIを追加する。
- intrinsic content size、content hugging、compression resistanceを扱えるようにする。
- fixed frame／autoresizingとconstraint layoutの利用規則を定める。
- 複数property／constraintをまとめて反映するbatch updateとlayout invalidationを追加する。
- Stack、Grid相当の高水準layout helperを追加する。
- `SplitView` のdivider style／thickness、collapse可否、resize distribution、divider位置eventを
  parameter化し、user drag後のnative stateをDart cacheへ同期する。

完了条件:

- 入れ子になったform layoutがWindow resize、文字列長、表示切替に追従する。
- unsatisfiable constraintと不正なownershipをDart側で診断できる。

### [ ] G4 — View単位の入力、focus、action routing

達成目標: 入力と操作eventを、Windowではなく実際のView／Controlへ正しく配送する。

進捗: **部分実装**。scroll、terminal input-client向けkey routing、first responder設定は
追加済みだが、汎用のView単位event／focus APIにはなっていない。

実装済み:

- event protocol v5に、flipped Window content座標、精密delta、scroll／momentum phase、
  device inversion、modifierを持つtyped `AppKitScrollEvent` を追加した。
- `KeyEventRouting.appKitOnly` を追加し、menu shortcut処理後のkeyをDartのWindow eventへ
  重複配送せず、first-responder／`NSTextInputClient` chainだけへ渡せるようにした。
- v1〜v7のstrict encoder／decoder、旧protocol filtering、有限値／phase検証を追加した。
- `Window.makeFirstResponder(View)` を追加し、同じWindowのcontent hierarchy内にあるViewだけを
  AppKit first responderへ設定できるようにした。
- package-createdな基底／簡易text viewのfocus可否を `ViewConfiguration` で選択可能にした。

未実装:

- mouse、key、scrollをview handle発生元のtyped event streamへ拡張し、hit-test／
  view-local coordinate情報を追加する。
- mouse enter/exit、hover、modifier changeを追加する。
- drag captureと、必要なgesture、magnify、rotate、swipe、pressure eventを追加する。
- first responderの取得／解除、Tab traversal、View単位focus change eventを追加する。
- Button、Menu、shortcutから共有できるaction／command routingの基礎を追加する。
- mouse move、scroll、frame eventのcoalescing／backpressure方針を実装し、入力遅延の
  無制限な蓄積を防ぐ。

完了条件:

- nested View間でpointer、keyboard、focusが正しいsourceへ一度だけ配送される。
- 通常AppKit responder modeとraw-input modeの既存挙動が維持される。

### [ ] G5 — 編集可能テキスト、IME、Undo

達成目標: 日本語を含む実用的なテキスト入力・編集をDartアプリケーションで扱える
ようにする。

進捗: **部分実装（terminal専用IME＋汎用multiline editor基盤）**。custom terminal Viewの
IME bridgeに加え、標準 `NSTextView` を使う汎用の編集surfaceが動作している。

追補タスク:

- [x] full-width line highlight付き`TextEditor`の初回glyph paintをkey入力なしで成立させる。

実装済み:

- `TerminalMetalView` に `NSTextInputClient` を実装し、raw key down/up、marked textの
  preedit、commit、cancelを型付き `TerminalTextInputEvent` として非同期配送する。
- textを1 field 64 KiB UTF-8、queueを256 event／1 MiBに制限し、隣接preeditのcoalescingと
  明示的overflow event、copy ownership、attach／detach lifecycleを実装した。
- candidate-window位置を同期Dart callなしで返すgeneration付きnative caret cacheと、
  Dart側の `publishCaretRect` を実装した。
- staged AppKit selector acceptanceでraw／preedit／commit／cancelとcandidate geometryの更新を
  検証し、ASCII、CJK、accent、emoji、modifier、key repeatを固定matrixで検証した。
- 表示専用 `TextView` のmonospaced/system/exact named font、font size／weight、padding、
  dynamic system／fixed sRGB foreground/backgroundと、基底focus／autoresizeをimmutable
  creation configurationとして実装した。
- scroll可能な汎用 `TextEditor` として、同一native surface上のeditable切替、16 MiB UTF-8
  text、UTF-16 selection、65,536件までのordered non-overlapping foreground／underline
  run、marked-text付きsnapshot、foreground／underline／selectionと独立したfull-width
  logical-line background、現在selectionを明示的にviewportへ入れるreveal操作を実装した。
  style-only更新とrevealはtext storage、selection、syntax属性を置換せず、command／editing
  modeで同じsyntax projectionを維持できる。
- `TextEditor` のnative selection／first responder／IME input client／Undo基盤を標準
  `NSTextView` に保持し、Dart fake、warning-clean native契約、current／legacy FFIで境界を
  検証した。

未実装:

- 現在の表示専用 `TextView` と区別したLabel、single-line TextField、SecureTextFieldを
  追加する。
- terminal専用event／caret contractを汎用のeditable Controlへ拡張し、text、selection、
  replacement range、marked text、surrounding text、commit／cancel compositionを扱う。
- native TextField／TextEditorとcustom Viewの双方で使えるIME、dead key、candidate-window、
  input-source切替の共通bridgeを追加する。
- change、submit、selection、validation eventとcontrolled/uncontrolled stateの規則を
  追加する。
- cut/copy/paste/select-all、Undo/Redo、find、必要なspell-check integrationを追加する。
- 実際の日本語IME／dead key／candidate UI／入力source切替を使うGUI integration testを
  追加する。現在の固定matrixは決定的なnative acceptanceであり、実OS入力sessionの代替ではない。

完了条件:

- 日本語IME、英語dead key、絵文字、selection、Undo/Redo、secure inputをGUI testで
  検証できる。
- focus traversalと標準編集shortcutがAppKitの期待どおり動作する。

### [ ] G6 — アクセシビリティとsemantic tree

達成目標: native controlとcustom-rendered viewの両方をVoiceOverとキーボードだけで
操作できるようにする。

進捗: **部分実装（terminal専用）**。terminal Viewは読み取り専用text areaとして公開済みだが、
汎用semantic treeとControl統合は未実装である。

実装済み:

- `TerminalAccessibilityViewSnapshot` に、boundedなvisible text、canonical UTF-16 line、
  terminal-column境界、selection、cursor、cell geometry、generationを持たせ、Dart/native双方で
  topology、range、surrogate境界、容量を検証して原子的に置き換える経路を実装した。
- `TerminalMetalView` を読み取り専用AppKit accessibility text areaとして公開し、range、line、
  attributed text、point lookup、screen-coordinate frame queryをnative snapshotだけで処理する。
- 値／selectionが変化した場合だけnotificationを送り、first responder時のfocused element、
  cursor line／range frame、stale／malformed snapshot拒否をnative acceptanceで検証した。

未実装:

- role、label、help、value、enabled、selected、expanded、range、actionを表す
  semantics APIを追加する。
- semantic parent/children、focus、hit testing、frame、value-change notificationを
  AppKit accessibilityへ接続する。
- native controlでは標準semanticsを保持し、custom viewではDartからsemantic treeを
  提供できるようにする。
- accessibility identifierと自動UI test向けqueryを追加する。
- 実VoiceOver processとkeyboard navigationを使い、読み上げ、selection、focus移動、
  View破棄／再配置を検証するGUI integration testを追加する。

完了条件:

- form、text editor、list、custom viewをVoiceOverとkeyboard navigationで操作できる。
- semantics更新、破棄、View再配置時にstale accessibility elementが残らない。

### [ ] G7 — 基本コントロールとcontainer

達成目標: 設定画面や一般的なformを、application固有Objective-Cコードなしで構築
できるようにする。

進捗: **部分実装（2-pane helper／簡易TextView）**。標準Control群はまだ実装されていない。

実装済み:

- 通常の `View` としてnested compositionできるnative `TwoPaneSplitView` helperを追加した。
- 2つのordered child、axis、fraction、minimum extent、equalize、one-child zoomを型付きDart APIで
  操作できる。
- 表示専用 `TextView` のfont、padding、foreground／background colorと基底View behaviorを
  immutable creation configurationで選択可能にした。

未実装:

- Label、Button、Link、Checkbox、Radio、Switch、Segmented Controlを追加する。
- Slider、Stepper、Progress Indicator、Popup／Combo Box、Image Viewを追加する。
- 明示済みの `TwoPaneSplitView` helperとは別に、複数child、divider
  appearance／thickness、collapse／resize behavior、状態eventを持つ汎用Split containerを提供する。
- Scroll、content-level Tab、Boxなど残りの基本containerを追加し、G3のlayout helperと統合する。
- enabled、hidden、title、value、state、image、tooltipなどの共通状態とaction eventを
  型付きDart APIとして公開する。
- native側でユーザー操作により変化する状態とDart側stateの同期規則を実装する。

完了条件:

- 設定画面と入力formのsampleをDartのみで構築できる。
- 各controlがlayout、focus、IME、accessibility、action routingへ統合されている。

### [ ] G8 — 大量データ向けView

達成目標: ファイル一覧、設定一覧、ログ、階層データなどを効率良く表示・操作できる
ようにする。

実装内容:

- Table/List、Outline、Collection相当のViewを追加する。
- data source、cell reuse、virtualization、incremental/diff updateを追加する。
- selection、multi-selection、sorting、column、inline editing、keyboard navigationを
  追加する。
- Sidebar、source list、context menuとの統合を追加する。

完了条件:

- 大量項目を全件View生成せずに表示し、scroll中もUI responsivenessを維持する。
- selectionとデータ更新がDart model、native view、accessibilityで一致する。

### [ ] G9 — 描画、media、style、animation

達成目標: AppKit標準controlでは表現できない画面を、共通の描画・media APIで実装
できるようにする。

進捗: **部分実装（terminal専用）**。次の機能は
`dart_terminal_renderer_macos` 内で実装済みだが、汎用GUI APIではない。

実装済み:

- CoreText font catalog、fallback、metrics、run shaping、top-down glyph rasterization。
  Core Graphics変換後のrow方向を非対称glyphの1x／2x testで固定している。
- build-time compiled Metal shader、bounded alpha／color atlas texture、dirty-rectangle upload、
  full-snapshot atlas reset、ordered instance frame、同期RGBA readback。
- custom View binding、on-demand presentation、triple-buffer submission、backpressure、
  GPU completionを含むslot retirement。
- drawable miss時のREADY保持と明示的presentation retry、生成／runtime failureの型付き状態。
- typed Dart frame encoder／renderer facade、generation／容量／layer順の検証、GPU timing／
  atlas uploadを含むbounded metrics。

未実装:

- `Color`、`Font`、`Image`、alignment、transform、clip、pathなどの共通値型を追加する。
- redraw request、dirty region、backing scale、color space、display-link／frame callbackを
  扱う汎用render surface契約を追加する。
- terminal固有ABIに依存しない、Core GraphicsまたはMetal capability向けdrawing boundaryを
  定める。
- bundle／memoryからの画像decode、scale variant、cache、native image表示を追加する。
- 汎用のtext measurement／shaping、layer、opacity、basic animationを追加する。
- light/dark appearance、accent、high contrast、reduced motion、locale、RTL変更を
  View／styleへ反映する。

完了条件:

- resizeとRetina倍率変更に追従するcustom drawing sampleを実装できる。
- animationや高頻度redrawがAppKit inputとDart messageをstarveしない。

### [ ] G10 — Window管理とApplication lifecycleの拡張

達成目標: document app、utility app、複数Window app、menu-bar appに必要なmacOS
window/application操作を提供する。

進捗: **部分実装**。outer frame、native fullscreen、window tab、最小presentation metadata、
基本window styleとRunner lifecycle policyが利用できるが、Window種類とtab／presentationの
設定範囲は限定的である。

実装済み:

- finiteかつ正のouter `Window.frame` を取得／変更でき、negative screen originを許容する。
  生成時もsetterと同じouter-frame contractを使い、Dart cacheを成功時だけ更新する。
- event protocol v6にdeduplicateされた `WindowFrameChangedEvent` と
  `WindowFullscreenChangedEvent` を追加し、show、move／resize、fullscreen完了／失敗を観測する。
- fullscreenは非同期requestと観測stateを分離し、同じtargetをidempotentに扱い、transition中の
  逆targetを拒否する。transition frameを抑制し、stateを先に通知してwindowed frameを保全する。
- 1 tabを1 `Window` としてnative tab groupへの追加／分離／選択を実装し、各Windowのevent、
  content view、handle identityを維持する。
- caller指定のabsolute `representedFilePath` とsRGB `WindowTabColor` を設定／解除し、
  standard proxy icon／path menuとtab accessory markerへ反映する。
- boundedなwidth／heightとrectangle／ellipse shapeを持つ `WindowTabAccessory` を実装し、
  旧 `Window.tabColor` を8×8 ellipseの互換helperとして維持する。
- `WindowConfiguration` でtitled／closable／miniaturizable／resizable styleを選択可能にし、
  従来の4-style windowを互換defaultとして維持する。
- 起動前manifest／`RunnerConfiguration` でactivation、launch activation、last-window close、
  reopen handled policyを選択可能にし、従来挙動を互換defaultとして維持する。
- event protocol v7にapplication-scopedなeffective light/dark appearance snapshot／changeを
  追加し、typed cache／stream、KVO deduplication、再登録／shutdown cleanupを実装した。

未実装:

- center、min/max size、aspect ratioを追加する。
- minimize、restore、zoom、hide、order、key/main window操作とeventを追加する。
- live-resize begin/end、fullscreen transition begin/endなど、完了snapshot以外の状態eventを追加する。
- tab groupの列挙／順序変更／selected state event、tabbing mode／identifier／overviewなどを追加する。
- configurable style mask、titlebar、toolbar、transparency、window levelを追加する。
- sheet、modal／modeless panel、child windowを追加する。
- Window registry、複数Window lifecycle、last-window close policy、state restorationを
  追加する。
- regular/accessory/prohibited activation policy、Dock menu／badge、status itemを追加する。
- screen列挙、座標変換、sleep/wake、sessionを追加する。

完了条件:

- multi-window document sampleとmenu-bar utility sampleを同じruntime上で実装できる。
- Window状態のDart cacheとnative stateが外部ユーザー操作後も一致する。

### [ ] G11 — Command、Menu、Pasteboard、Drag & Drop

達成目標: macOS標準のcommand操作とアプリケーション間データ交換を一貫して扱える
ようにする。

進捗: **部分実装**。固定構造のMenuとplain-text pasteboardだけが利用できる。

実装済み:

- main menu、submenu、separator、shortcut、enabled stateと、application／MenuItem streamへの
  action routingを実装した。
- `MenuConfiguration` で明示的enabled stateとAppKit auto-enablementをmenuごとに選択可能にした。
- general pasteboardのplain text read／write／clear／change countを実装した。
- generic／specialized ViewにAppKit標準のcontext menuを接続し、View/Menuのどちらを
  解放してもnative/Dart双方の所有状態を解除する仕組みを実装した。
- generic／specialized／provider-owned Viewにstage-2 pressure requestを登録し、有限な
  View-local座標をv9 eventで非同期配送して、boundedな単語・font・baselineをAppKit標準の
  definition overlayへ表示する仕組みを実装した。
- nativeからのtext readを64 MiB UTF-8に制限し、超過時はoutputを空のまま
  `limit exceeded` として失敗させ、partial dataを公開しないcontractを実装した。
- generic／specialized／provider-owned Viewへ、bounded plain-text selectionと
  returned-text上限をnative snapshotとして保持するServices requestorを実装した。同期AppKit
  callbackはDartへ再入せず、returned textをgeneration-checked v10 eventで非同期配送する。
- generic／specialized／provider-owned Viewへcopy-onlyのplain-text／local file-URL drop
  destinationを実装した。window ancestryで最深targetを同期選択し、bounded performだけを
  generation-checked v11 eventで非同期配送する。

未実装:

- Button、Menu、keyboard shortcut、toolbar itemで共有するtyped `Command` modelを
  追加する。
- MenuItemのtitle、shortcut、checked/mixed、hidden、alternate、image、dynamic
  validationを追加する。
- MenuItemのinsert/remove/reorderと、About、Settings、Hide、Services、Window、Help、
  Editなど標準menu roleを追加する。
- PasteboardをUTTypeベースに拡張し、file URL、image、rich text、custom data、
  複数representationを扱えるようにする。
- 64 MiBをnative hard maximumとして維持しつつ、applicationが用途ごとにより小さい
  `maxUtf8Bytes` を指定してcopy前に拒否できるread APIを追加する。
- copy/paste availability、pasteboard change、lazy data providerを追加する。
- View単位のdrag source、copy以外のoperation negotiation、file promiseを追加する。

完了条件:

- text、image、file、custom dataをcopy/pasteおよびdrag/dropできる。
- commandのenabled／checked状態がmenu、button、shortcut間で同期する。

### [ ] G12 — Dialog、Document、macOSサービス統合

達成目標: ファイルを扱う一般的なデスクトップアプリケーションに必要なsystem UIと
application delegate eventを提供する。

進捗: **部分実装**。送信方向のallowlist付き外部URL起動だけを先行実装している。

実装済み:

- `AllowedExternalUrl` をclosedな値型として追加し、最大4096 UTF-8 bytes、
  control／whitespace／backslash／bidi／malformed escape／UTF-16拒否をDartとnativeの
  両方で検証する。immutableな `ExternalUrlPolicy` がscheme別のauthority／host／
  credentials／path条件を所有し、HTTP／HTTPS／mailtoは互換defaultとして保持する。
- `AppKitApplication.openExternalUrl` が検証済みの同一文字列だけをmain thread上の
  `NSWorkspace.openURL` へ渡し、Launch Servicesの受理結果を `bool` で返す経路を実装した。
  shell commandや文字列補間は使用しない。
- optionalなABI entryとtest recorderにより、旧bridgeではunsupportedとして安全に失敗し、
  test中に実browser／mail applicationを起動せずvalidationとdispatchを検証できる。
- application policyを渡すadditive ABI entryを実装し、旧entryへは互換defaultと完全一致する
  場合だけfallbackする。custom scheme／条件は旧bridgeでunsupportedとして拒否する。
- `NSApplication.servicesProvider`へboundedなfolder Services providerを接続した。
  primary／secondary callbackはlocal file URLだけをfilesystem metadataでdirectory自身または
  fileの親へ正規化し、順序を保って重複排除したv12 application eventを非同期配送する。

未実装:

- Open Panel、Save Panel、Alert、Color Panel、Font Panelを非同期APIとして追加する。
- applicationへのopen files、open URLs、reopen、user activity eventを追加する。
- recent documents、file association、URL scheme、security-scoped bookmarkを追加する。
- Finderで表示、file／directoryを既定applicationで開くなど、残りの安全な `NSWorkspace`
  操作を追加する。
- user notificationなどのoptional capabilityが必要とするapplication activation eventと
  manifest連携を追加する。
- modal operationでもnative delegateからDartへ同期再入しないrequest/result modelを
  維持する。

完了条件:

- sandboxを想定したopen/edit/save lifecycleを持つdocument sampleを実装できる。
- cancel、Window close、application termination時にpending dialogが安全に完了する。

### [ ] G13 — Background helper transportとsupervision

達成目標: CPU負荷の高い処理や障害分離が必要な処理を、UIを停止させず外部Dart
helperへ委譲できるようにする。

実装内容:

- manifest-declared helperの起動、終了、stdin/stdoutまたはsocket transportを扱う
  optional runtime APIを追加する。
- request identity、response、streaming、cancellation、timeout、bounded queue、
  backpressureの共通framingを追加する。
- helper crash、restart、shutdown escalation、orphan prevention、diagnosticsを追加する。
- payload schemaと製品固有のrecovery policyはapplication側に残す。
- UI更新は必ずroot isolateへ戻してからAppKitを呼ぶ契約を検証する。

完了条件:

- 長時間のCPU taskと大量streamをhelperで処理しても、Window操作が応答し続ける。
- helper failure、cancel、application終了時にprocessとrequestが残らない。

### [ ] G14 — 公開Testing APIとGUI検証基盤

達成目標: application packageがnative GUIを起動せずに大部分をunit testでき、必要な
箇所だけを実GUI／画像／accessibility testで検証できるようにする。

進捗: **既存機能向け内部基盤と限定的な公開hookは実装済み、汎用Testing APIは未実装**。

実装済みの検証基準:

- coreのfake bindings、native contract、event encoder、legacy bridge、JIT／AOT FFI smokeを
  実装している。`package:dart_appkit/testing.dart` からraw event injection、native Window handle、
  attach helper、deferred application-termination requestをproduction exportと分離して公開した。
- event protocol v5 scroll、v6 frame／fullscreen、native tabs、SplitView、first responder、
  Window metadata、pasteboard read上限、外部URLの二重validation／recorderを実processまたは
  deterministic fakeで検証している。
- terminal rendererのstrict decoder、RGBA readback、one-shot fault injectionに加え、
  staged `NSTextInputClient` acceptance、input-source／repeat matrix、accessibility snapshot／
  AppKit selector／focus acceptanceを実装している。
- PTYのclosed parent stdin、process snapshot、consumer-selected read batch、consumer完了後ACK、
  configurable event-turn scheduling、EOF／destroy ownershipをnative／real Dartで検証している。

未実装:

- application、View tree、Control、layout、eventを扱う公開fake/test hostを追加する。
- 現在internal `NativeBindings` 型を要求するattach helperを、外部packageがprivate `src/` importなしで
  実装できるstable test-backend interfaceへ置き換える。
- pointer、keyboard、focus、IME、menu、window、capability event injectionを追加する。
- View tree／layout snapshot、screenshot／golden test、Retina scale別testを追加する。
- VoiceOver semantics、keyboard navigation、drag/drop、dialogのintegration test helperを
  追加する。
- native object leak、stale event、double release、capability instance lifetimeの共通
  conformance suiteを追加する。

完了条件:

- 外部application／capability packageがprivate `src/` APIなしでテストできる。
- 代表sampleにunit、native contract、GUI、golden、accessibility testが揃う。

### [ ] G15 — 開発体験とperformance tooling

達成目標: 一般的なGUIアプリケーションを短いiterationで開発し、UI停止や描画問題を
診断できるようにする。

進捗: **部分実装（terminal renderer専用metrics）**。

実装済み:

- `TerminalMetalRendererState` から、submission／completion／stale drop／backpressure、
  drawable miss、command failureを取得できる。
- 成功したGPU処理時間のsample数・合計・最大値と、受理したatlas uploadの件数・byte数を
  polling可能なsaturating counterとして公開した。

未実装:

- VM Serviceの安全な有効化と接続情報管理を追加する。
- incremental Kernel compilation、hot restartを追加し、可能な範囲でhot reloadを
  評価・実装する。
- View tree、layout constraint、focus、semanticsを確認できるdiagnostic inspectorを
  追加する。
- terminal専用counterを共通diagnosticsへ統合し、event latency、message-pump backlog、
  CPU／GPU frame time、percentile、dropped/coalesced event、native handle数を時系列で
  計測できるtraceを追加する。
- contributorが巨大なEngine checkoutを毎回保持しなくてよい、検証済みprebuilt
  Engine cache／artifact取得経路を追加する。

完了条件:

- 小規模なDart UI変更をfull rebuild／手動再起動なしで確認できる。
- input latency、jank、layout、resource leakを標準toolingで特定できる。

### [ ] G16 — Production packagingと配布

達成目標: 生成したapplicationを開発用ad-hoc bundleではなく、署名・notarizeされた
配布可能なmacOS applicationとして生成できるようにする。

実装内容:

- manifestを拡張し、build number、icon、application category、copyright、
  localized resources、document type、URL scheme、privacy usage descriptionを扱う。
- 安全に制約されたInfo.plist追加項目とentitlements設定を追加する。
- Developer ID signing、hardened runtime、notarization、staplingを追加する。
- App Sandbox、security-scoped resource、App Store向けbuild profileを追加する。
- arm64／x86_64のbuildとUniversal Binary assemblyを追加する。
- dSYM、crash symbol、archive、release metadata、CI artifact生成を追加する。
- pinned Dart SDK／Engineのupgrade、互換性検証、release artifact管理手順を追加する。

完了条件:

- 同一sampleからnotarized Developer ID buildとsandboxed buildを再現可能に生成できる。
- clean machineで署名、notarization、bundle内容、arm64/x86_64起動を検証できる。

## 推奨milestone

### Milestone 1 — 基本的なnative GUI

対象: **G0〜G7**

完了像: 設定画面や小規模formを、View階層、layout、標準control、IME、keyboard、
VoiceOverを含めてDartから構築できる。

### Milestone 2 — 一般的なdesktop application

対象: **G8〜G13**

完了像: 大量データ、custom drawing、複数Window、document、clipboard／drag-drop、
system dialog、background helperを利用するアプリケーションを構築できる。

`G9` のcustom renderingは、native control中心のアプリケーションではG7と並行して
進められる。`G13` もUI基礎とは独立性が高いため、CPU-heavyな最初の製品が必要とする
時点で前倒しできる。

### Milestone 3 — 開発・出荷可能なSDK

対象: **G14〜G16**

完了像: 外部packageが安定したtesting APIと開発toolを利用でき、生成物を署名、
notarize、sandbox化して配布できる。

## 別トラック

### [ ] X0 — Terminal renderer本体（部分実装）

達成目標: terminal screen stateをboundedな描画データへ変換し、mixed-script text、
cursor、selectionを含む画面を低遅延かつ安全に `TerminalMetalView` へ表示する。

実装済み:

- paused／on-demand／framebuffer-onlyのflipped `MTKView` shell。
- generation-owned CoreText font catalog、style／fallback解決、terminal cell／decoration
  metrics。
- bounded run shaping、UTF-16 cluster mapping、Dart-owned bounded LRU shaping cache。
- unique glyph batchのtop-down alpha8／RGBA8 rasterizationとbacking scale対応。
  Core Graphics変換後のrow二重反転を除去し、非対称glyphでorientationを固定している。
- precompiled Metal shader、bounded alpha／color texture array、atlas dirty-rectangle upload、
  snapshot／page generation検証、全sliceをclearするgeneration-safe `resetAtlas`。
- background、selection、alpha／color glyph、decoration、cursorをlayer順に表せるpacked
  instance frameとtyped Dart encoder。
- deterministic offscreen RGBA readbackと、Viewへbindした3-slot production submission。
- newest-ready選択、stale frame drop、即時backpressure、GPU完了後のretirement state。
- typed creation／runtime failure state、fault後のadmission停止、drawable miss時のREADY保持と
  明示的 `requestPresentation`。
- GPU timing、atlas upload量、submission、drop、backpressure、drawable miss、command
  failureを取得できるbounded renderer metrics。
- `NSTextInputClient` によるraw key／preedit／commit／cancel、bounded queue／overflow、
  generation付きcandidate caret cacheを型付きDart APIとして提供するterminal text-input境界。
- visible text、UTF-16 line／terminal-column mapping、selection、cursor、cell geometry、logical content originのbounded
  snapshotを使い、同期Dart callなしでAppKitの読み取り専用accessibility text areaを提供する境界。

未実装:

- terminal grid／cell／line modelと、PTY／parser側screen snapshotをrenderer入力へ変換する
  境界を実装する。
- wide character、combining sequence、ligature、fallback run、RTLをterminal cellへ配置する
  高水準layoutとclipping policyを実装する。
- Dart-owned glyph atlas allocator／packer、page reuse、eviction、raster cache、residency／pin
  管理を実装する。native側のtexture pageとdirty uploadだけではatlasは完成していない。
- screen差分からdamage regionを計算し、必要なcell、glyph upload、instanceだけを更新する
  pipelineを実装する。
- terminal stateから背景、glyph、underline／strike、cursor、selectionのordered instanceを
  構築するframe builderを実装する。
- cursor shape／blink／focus、selection range／色／IME marked rangeなどの高水準表示挙動を
  実装する。
- `TerminalTextInputClient` のraw／preedit／commit／cancel／overflowを実terminal sessionの
  command／byte encoding／composition stateへ接続し、focus／routing lifecycleを管理する。
- terminal cursorから最新のlocal caret rectangleを計算して `publishCaretRect` へ接続し、
  resize、scroll、font／scale、preedit更新後もcandidate geometryを同期させる。
- 実screen stateから `TerminalAccessibilityViewSnapshot` を生成し、wide／combining cellを含む
  UTF-16 column mapping、selection、cursor、geometryの変更時に単調なgenerationで公開する。
- resize、backing-scale、font、theme、color-space変更時の再layout／再raster／atlas再構築を
  実装し、必要な時に既存 `resetAtlas` でfull snapshotを開始して再populateする。
- Windowのvisibility／occlusion／resume eventを `requestPresentation` に接続し、drawable
  miss後にREADY frameを再提示する時点と重複要求の抑制policyを実装する。
- backpressure時の再試行、frame coalescing、retirement watermarkに基づくatlas pin解放を
  renderer ownerへ統合する。
- typed faultを監視し、rendererの破棄・再生成・Viewへの再binding・atlas／frame再送を行う
  recovery controllerと、回復不能時にapplicationへ通知するpolicyを実装する。
- renderer metricsを定期収集し、許容frame time、drop、backpressure、upload量の基準と
  diagnostics出力を定める。
- 実PTY sessionを使い、mixed-script、emoji、Retina変更、resize、rapid update、
  drawable miss、command failure、resource bound、実input source／IME candidate、VoiceOverを
  検証するend-to-end／performance testとsampleを追加する。
- 汎用View／Controlの入力、IME、semantic treeはG4〜G6で実装する。terminal packageには
  先行する専用adapterだけを置き、terminal byte encoding、composition、semantics、描画の
  製品policyは引き続きterminal ownerが保持する。

完了条件:

- 実terminal screenをcursor／selection／装飾込みで表示し、resizeと1x／2x切替後もcellと
  glyphが一致する。
- 継続的な大量出力でもqueue、atlas、frame slotが設定上限を越えず、入力応答を維持する。
- stale generation、backpressure、drawable miss、Metal command／device fault、View破棄、
  renderer破棄から安全に回復できる。
- IMEのpreedit／commit／candidate位置と、VoiceOverへ公開するtext／selection／cursor／frameが
  実terminal stateと一致し、native callbackからDartへ同期再入しない。

### [ ] X1 — クロスプラットフォーム化（将来検討）

macOS以外も対象にする場合は、Window、View、input、text、semantics、render surfaceを
platform-neutral interfaceとして再定義し、Windows／Linux hostとbackendを追加する。
これは `dart_appkit` の単純な機能追加ではなく、別packageまたはmajor-version規模の
作業とし、macOS向けMilestone 1〜3の前提にはしない。

### [ ] X2 — 選択的なmacOS capability package

WebView、PDF、camera、media playback、system notificationなど、一般的ではあるが
すべてのapplicationが必要としない機能は、G1のinstance／event契約を利用する独立
packageとして実装する。各packageは固有framework、permission、Info.plist、
entitlementを所有し、汎用bridgeやrunnerの必須依存にはしない。

## 現時点で意図的に汎用core外へ残すもの

- application固有の状態管理、navigation、business logic、data model。
- helper processのpayload schema、再試行判断、製品固有のrecovery policy。
- terminal protocol、shell policy、pane/session recovery。
- database、network clientなど、AppKit基礎層に属さない個別機能。
- UI toolkit全体を独自描画する場合のWidget modelとdesign system。
