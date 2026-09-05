# Dart AppKit — 汎用 macOS GUI ロードマップ

## 目的

このロードマップの目的は、現在のターミナル向け基盤を中心とした
`dart_appkit` と `dart_macos_runtime` を、Dartから一般的なmacOS GUI
アプリケーションを構築できる基盤へ段階的に拡張することである。

現在の実装は、AppKitメインスレッド上でDartを安全に実行し、1枚の専用
ビューへ低水準の入力を届ける用途には適している。一方、フォーム、設定画面、
テキストエディタ、ファイルブラウザ、データ一覧などを実装するには、ビュー階層、
レイアウト、標準コントロール、テキスト入力、アクセシビリティ、macOSサービス
との統合が不足している。

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
- 現在進行中の汎用GUIタスクはない。
- 次に着手する推奨タスクは **G0 — 汎用GUIの公開契約と境界の確定**である。
- 現在の検証済み基準は、arm64上のDeveloper JIT／Release AOT、Timer動作、
  ウィンドウ・メニュー・入力イベント、close/terminate応答、native handle解放、
  capability loading、PTY、process exit 0である。

## 実装済みの基盤

以下は旧T0〜T14と、その過程で追加された実装を機能別に再整理したものである。
詳細な時系列と判断理由は `docs/WORKLOG.md`、検証結果は
`docs/VERIFICATION.md` を正とする。

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
- 汎用 `View`、表示専用の簡易 `TextView`、Windowへの単一content view設定を実装。
- dependencyが登録したnative `NSView` を `View.custom()` で生成できる仕組みを実装。

### [x] B3 — 入力イベントとキー配送

- Windowを発生元とするmouse down/up/move/dragイベントを実装。
- key down/up、key code、modifier、repeat、charactersをDartへ配送。
- 通常のAppKit responder chainも通す既定modeと、メニューshortcutを優先した後で
  Dartだけへ配送するraw-input modeをWindow単位で選択可能にした。
- input、window、application eventをversion 1〜4でdecode／routeする仕組みを実装。

### [x] B4 — MenuとプレーンテキストPasteboard

- main menu、submenu、separator、shortcut、enabled state、menu action eventを実装。
- applicationとMenuItem固有streamへのaction routingを実装。
- general pasteboardのplain text read/write/clear/change countを実装。
- Unicode、空文字、値なし、NULを含む文字列、native failureを検証。

### [x] B5 — Native capability／native asset基盤

- versioned native-extension service tableと、名前付き `NSView` factory登録を実装。
- manifestに宣言したcapability dylibのbuild hook、staging、ABI検証、初期化、
  process-lifetime image retentionを実装。
- Objective-C pointerをapplication Dartへ公開せず、生成したviewを通常の
  generation-checked handleとして管理。
- AppKitへ登録しない独立native assetのbuild／staging経路も実装。

### [x] B6 — 再利用可能なmacOS application runtime

- `dart_macos_runtime` とstrict JSON application manifestを実装。
- 同じDart `main(List<String>)` からDeveloper JIT／Release AOT bundleを生成。
- application identity、minimum macOS version、resources、native assets、
  native capabilities、diagnosticsの宣言と検証を実装。
- application-owned Dart helperを自己完結実行ファイルとして
  `Contents/Helpers` にbuild／stageする機能を実装。
- bundle resource、Framework、helperの安全なpath lookupを実装。
- privacy-bounded lifecycle diagnosticsとad-hoc signingを実装。

### [x] B7 — ターミナル向け独立機能

- `dart_terminal_renderer_macos` に、paused／on-demand／framebuffer-onlyの
  `MTKView` shellとnative capability境界を実装。
- `dart_pty_macos` に、AppKit非依存のPTY生成、非同期read/write、bounded queue、
  backpressure、resize、signal、graceful/forced close、exit/reapを実装。
- terminal-specific protocol、renderer、recovery policyを汎用hostから分離。

注意: `TerminalMetalView` は現在rendererの入れ物までであり、terminal grid、
glyph shaping、atlas、shader、draw submissionなどの描画本体はまだ実装済みではない。

### [x] B8 — Build、検証、サンプル

- 公式Dart SDK revisionの検証とEngine build bootstrapを実装。
- `dart_appkit:run`、manifest-driven builder、bundle assembly、stdio／argument／
  exit-code forwardingを実装。
- hello-windowのJIT/AOT GUI smoke、native bridge test、C/C++ header test、
  FFI smoke、Dart analysis/unit testを実装。
- native handle churn、wrong-thread、stale event、event encoding、capability lifetime、
  PTY integrationを含むregression suiteを実装。

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

### [ ] G0 — 汎用GUIの公開契約と境界の確定

達成目標: 後続のGUI機能を互換性のある形で追加できる、最小の公開モデルを確定する。

実装内容:

- AppKit native-control中心のハイブリッド方式を正式な対象モデルとして定義する。
- `dart_appkit`、`dart_macos_runtime`、optional capability package、applicationの
  責任境界を確定する。
- View、Control、event、layout、semantics、native capability instanceの公開概念と
  versioning方針を定義する。
- 設定画面、テキスト入力画面、一覧画面、custom drawing画面を代表use caseとして、
  後続milestoneの受け入れ条件を定める。
- 既存APIとABIを維持する範囲、追加API、非推奨化が必要なAPIを整理する。

完了条件:

- 後続G1〜G16が依存できる公開境界と互換性ルールが文書化されている。
- 既存hello-window、terminal capability、JIT/AOT runtimeを壊さない移行方針がある。

### [ ] G1 — 対話的native capability instance

達成目標: 外部packageが、複数の対話的native Viewを型付きDart APIとして安全に
提供できるようにする。

実装内容:

- 現在のゼロ引数View factoryを拡張し、生成設定を渡せるversioned capability ABIを
  追加する。
- host側Viewとcapability側instanceを一対一に対応付ける、安全なopaque identityと
  lifecycle契約を追加する。
- instance単位のproperty update、command、state query、event deliveryの共通経路を
  追加する。
- capability eventにprovider namespace、instance source、protocol versionを持たせる。
- raw Objective-C pointerや任意のregistry handleをDartへ公開せずに操作できるようにする。
- 外部packageが型付きView wrapperを提供できるDart拡張APIとtest backendを追加する。

完了条件:

- 1つのcapabilityから複数instanceを生成し、個別に状態更新・event受信・破棄できる。
- old service-table clientと既存 `View.custom()` がそのまま動作する。

### [ ] G2 — View階層、geometry、共通property

達成目標: 1つのWindow内に複数のViewを安全に構成できるようにする。

実装内容:

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

実装内容:

- AppKit Auto Layoutを安全に表現するanchor、constraint、priority APIを追加する。
- intrinsic content size、content hugging、compression resistanceを扱えるようにする。
- fixed frame／autoresizingとconstraint layoutの利用規則を定める。
- 複数property／constraintをまとめて反映するbatch updateとlayout invalidationを追加する。
- Stack、Grid相当の高水準layout helperを追加する。

完了条件:

- 入れ子になったform layoutがWindow resize、文字列長、表示切替に追従する。
- unsatisfiable constraintと不正なownershipをDart側で診断できる。

### [ ] G4 — View単位の入力、focus、action routing

達成目標: 入力と操作eventを、Windowではなく実際のView／Controlへ正しく配送する。

実装内容:

- view handleをsourceとするtyped event streamと、hit-test／local-coordinate情報を追加する。
- mouse enter/exit、hover、scroll wheel、modifier changeを追加する。
- drag captureと、必要なgesture、magnify、rotate、swipe、pressure eventを追加する。
- first responderの取得・設定、focus可否、Tab traversal、focus change eventを追加する。
- Button、Menu、shortcutから共有できるaction／command routingの基礎を追加する。
- mouse move、scroll、frame eventのcoalescing／backpressure方針を実装し、入力遅延の
  無制限な蓄積を防ぐ。

完了条件:

- nested View間でpointer、keyboard、focusが正しいsourceへ一度だけ配送される。
- 通常AppKit responder modeとraw-input modeの既存挙動が維持される。

### [ ] G5 — 編集可能テキスト、IME、Undo

達成目標: 日本語を含む実用的なテキスト入力・編集をDartアプリケーションで扱える
ようにする。

実装内容:

- 現在の表示専用 `TextView` と区別したLabel、single-line TextField、SecureTextField、
  multiline TextEditorを追加する。
- text、selection、replacement range、marked text、commit/cancel compositionを扱う。
- `NSTextInputClient` に必要なIME、dead key、candidate-window位置、surrounding textの
  bridgeを追加する。
- change、submit、selection、validation eventとcontrolled/uncontrolled stateの規則を
  追加する。
- cut/copy/paste/select-all、Undo/Redo、find、必要なspell-check integrationを追加する。

完了条件:

- 日本語IME、英語dead key、絵文字、selection、Undo/Redo、secure inputをGUI testで
  検証できる。
- focus traversalと標準編集shortcutがAppKitの期待どおり動作する。

### [ ] G6 — アクセシビリティとsemantic tree

達成目標: native controlとcustom-rendered viewの両方をVoiceOverとキーボードだけで
操作できるようにする。

実装内容:

- role、label、help、value、enabled、selected、expanded、range、actionを表す
  semantics APIを追加する。
- semantic parent/children、focus、hit testing、frame、value-change notificationを
  AppKit accessibilityへ接続する。
- native controlでは標準semanticsを保持し、custom viewではDartからsemantic treeを
  提供できるようにする。
- accessibility identifierと自動UI test向けqueryを追加する。

完了条件:

- form、text editor、list、custom viewをVoiceOverとkeyboard navigationで操作できる。
- semantics更新、破棄、View再配置時にstale accessibility elementが残らない。

### [ ] G7 — 基本コントロールとcontainer

達成目標: 設定画面や一般的なformを、application固有Objective-Cコードなしで構築
できるようにする。

実装内容:

- Label、Button、Link、Checkbox、Radio、Switch、Segmented Controlを追加する。
- Slider、Stepper、Progress Indicator、Popup／Combo Box、Image Viewを追加する。
- Scroll、Split、Tab、Boxなどの基本containerを追加し、G3のlayout helperと統合する。
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

実装内容:

- `Color`、`Font`、`Image`、alignment、transform、clip、pathなどの共通値型を追加する。
- redraw request、dirty region、backing scale、color space、display-link／frame callbackを
  扱うrender surface契約を追加する。
- Core GraphicsまたはMetal capabilityから利用できるdrawing boundaryを定める。
- bundle／memoryからの画像decode、scale variant、cache、native image表示を追加する。
- text measurement／shaping、layer、opacity、basic animationを追加する。
- light/dark appearance、accent、high contrast、reduced motion、locale、RTL変更を
  View／styleへ反映する。

完了条件:

- resizeとRetina倍率変更に追従するcustom drawing sampleを実装できる。
- animationや高頻度redrawがAppKit inputとDart messageをstarveしない。

### [ ] G10 — Window管理とApplication lifecycleの拡張

達成目標: document app、utility app、複数Window app、menu-bar appに必要なmacOS
window/application操作を提供する。

実装内容:

- current frameの取得・変更、move、center、min/max size、aspect ratioを追加する。
- minimize、restore、zoom、fullscreen、hide、order、key/main window操作とeventを追加する。
- move、resize、live-resize begin/end、fullscreen transitionなどの状態eventを追加する。
- configurable style mask、titlebar、toolbar、transparency、window levelを追加する。
- sheet、modal／modeless panel、child windowを追加する。
- Window registry、複数Window lifecycle、last-window close policy、state restorationを
  追加する。
- regular/accessory/prohibited activation policy、Dock menu／badge、status itemを追加する。
- screen列挙、座標変換、sleep/wake、session、application appearance changeを追加する。

完了条件:

- multi-window document sampleとmenu-bar utility sampleを同じruntime上で実装できる。
- Window状態のDart cacheとnative stateが外部ユーザー操作後も一致する。

### [ ] G11 — Command、Menu、Pasteboard、Drag & Drop

達成目標: macOS標準のcommand操作とアプリケーション間データ交換を一貫して扱える
ようにする。

実装内容:

- Button、Menu、keyboard shortcut、toolbar itemで共有するtyped `Command` modelを
  追加する。
- MenuItemのtitle、shortcut、checked/mixed、hidden、alternate、image、dynamic
  validationを追加する。
- MenuItemのinsert/remove/reorderと、About、Settings、Hide、Services、Window、Help、
  Editなど標準menu roleを追加する。
- context menuとView単位のmenu presentationを追加する。
- PasteboardをUTTypeベースに拡張し、file URL、image、rich text、custom data、
  複数representationを扱えるようにする。
- copy/paste availability、pasteboard change、lazy data providerを追加する。
- View単位のdrag source／drop target、operation negotiation、file promiseを追加する。

完了条件:

- text、image、file、custom dataをcopy/pasteおよびdrag/dropできる。
- commandのenabled／checked状態がmenu、button、shortcut間で同期する。

### [ ] G12 — Dialog、Document、macOSサービス統合

達成目標: ファイルを扱う一般的なデスクトップアプリケーションに必要なsystem UIと
application delegate eventを提供する。

実装内容:

- Open Panel、Save Panel、Alert、Color Panel、Font Panelを非同期APIとして追加する。
- applicationへのopen files、open URLs、reopen、user activity eventを追加する。
- recent documents、file association、URL scheme、security-scoped bookmarkを追加する。
- Finderで表示、既定applicationで開く、URLを開くなど `NSWorkspace` 操作を追加する。
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

実装内容:

- application、View tree、Control、layout、eventを扱う公開fake/test hostを追加する。
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

実装内容:

- VM Serviceの安全な有効化と接続情報管理を追加する。
- incremental Kernel compilation、hot restartを追加し、可能な範囲でhot reloadを
  評価・実装する。
- View tree、layout constraint、focus、semanticsを確認できるdiagnostic inspectorを
  追加する。
- event latency、message-pump backlog、frame time、dropped/coalesced event、native
  handle数を計測できるtraceを追加する。
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

### [ ] X0 — Terminal renderer本体

`dart_terminal_renderer_macos` 内でterminal grid、CoreText shaping、glyph atlas、
Metal shader、draw submission、cursor、selection、damage trackingを実装する。
汎用render surface、IME、accessibilityとの共有部分はG4、G5、G6、G9を利用するが、
terminal semanticsと描画policyは引き続きterminal packageが所有する。

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
