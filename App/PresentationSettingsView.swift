import SwiftUI

extension InterfaceTextSize {
    var dynamicSize: DynamicTypeSize? {
        switch self { case .system: nil; case .small: .small; case .standard: .large; case .large: .xLarge; case .extraLarge: .xxLarge }
    }
}

@MainActor
struct PresentationSettingsView: View {
    @ObservedObject var store: BrowserStore
    var body: some View {
        Form {
            Section("表示") {
                Stepper("タブ一覧：\(store.presentation.tabColumns)列", value: preference(\.tabColumns), in: 1...4)
                    .accessibilityIdentifier("tabColumnsStepper")
                Picker("アプリの文字サイズ", selection: preference(\.interfaceTextSize)) {
                    ForEach(InterfaceTextSize.allCases) { size in Text(size.label).tag(size) }
                }
                .accessibilityIdentifier("interfaceTextSizePicker")
                Text("ページの文字・表示倍率：\(Int((store.presentation.pageZoom * 100).rounded()))％")
                Slider(value: preference(\.pageZoom), in: 0.75...2, step: 0.05).accessibilityIdentifier("pageZoomSlider")
                Button("ページを100％に戻す") { var p = store.presentation; p.pageZoom = 1; store.updatePresentation(p) }
                Text("ページの倍率は文字に合わせて画像やレイアウトも拡大します。アプリ内の文字サイズとは別に設定できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("ホームインジケータを自動的に隠す", isOn: preference(\.hideHomeIndicator))
                Text("動画・音声の再生はbuild 14の方式を使用しています。").font(.footnote)
            } header: { Text("閲覧と再生") }
            footer: { Text("横画面のバーは最初は隠れ、ページの上側へ戻るスクロールで表示します。縦画面も下へ読み進めると隠れ、上へ戻すと表示します。ホームインジケータの一時表示はiOSが制御します。サイト側が再生を停止する場合や、通信・DRMの制限までは解除できません。") }
            Section {
                Toggle("アドレスバーの左右を個別に設定", isOn: preference(\.customAddressButtons))
                Text("縦画面にも左右のボタンを置けます。横画面は、個別設定がオフなら下段ツールバーのボタンを左右に並べます。ボタンが多いとアドレス欄が縮み、左右のボタン欄を横スクロールできます。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("アドレスバーのボタン") }
            addressSection(left: true)
            addressSection(left: false)
            Section {
                Button("アドレスバーの左右を標準に戻す") {
                    var p = store.presentation; p.customAddressButtons = false; p.addressLeft = []; p.addressRight = []; store.updatePresentation(p)
                    var controls = store.toolbar; controls.left = nil; controls.right = nil; store.updateToolbar(controls)
                }
                NavigationLink("ホーム背景の位置・ズーム") { BackgroundAdjustmentView(store: store) }
            }
            Section("保存した証明書の例外") {
                if store.connectionPreferences.certificates.isEmpty { Text("保存した例外はありません").foregroundStyle(.secondary) }
                ForEach(store.connectionPreferences.certificates.keys.sorted(), id: \.self) { origin in
                    Text(origin).font(.footnote).swipeActions { Button("削除", role: .destructive) { store.removeConnectionException(origin) } }
                }
            }
            Section {
                if store.connectionPreferences.httpOrigins.isEmpty { Text("保存した例外はありません").foregroundStyle(.secondary) }
                ForEach(store.connectionPreferences.httpOrigins, id: \.self) { origin in
                    Text(origin).font(.footnote).swipeActions { Button("削除", role: .destructive) { store.removeConnectionException(origin) } }
                }
            } header: { Text("HTTPで開くローカル接続先") }
            footer: { Text("例外は接続先ごとに保存します。証明書の変更時は再確認します。削除は次回の接続確認から適用され、現在の接続を強制切断しません。") }
        }
        .navigationTitle("表示・操作")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }
    private func preference<Value>(_ path: WritableKeyPath<PresentationPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.presentation[keyPath: path] }, set: { value in var p = store.presentation; p[keyPath: path] = value; store.updatePresentation(p) })
    }
    private func addressSection(left: Bool) -> some View {
        let values = left ? store.addressLeftActions : store.addressRightActions
        return Section {
            ForEach(values) { action in Label(action.label, systemImage: action.symbol) }
                .onMove { source, destination in editAddress(left: left) { $0.move(fromOffsets: source, toOffset: destination) } }
                .onDelete { offsets in editAddress(left: left) { $0.remove(atOffsets: offsets) } }
            let missing = AddressBarAction.allCases.filter { !values.contains($0) }
            if !missing.isEmpty {
                Menu {
                    ForEach(missing) { action in Button(action.label, systemImage: action.symbol) { editAddress(left: left) { $0.append(action) } } }
                } label: {
                    Label("ボタンを追加", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier(left ? "addAddressLeftButton" : "addAddressRightButton")
            }
        } header: { Text((left ? "左側" : "右側") + "（\(values.count)個）") }
    }
    private func editAddress(left: Bool, operation: (inout [AddressBarAction]) -> Void) {
        var p = store.presentation; p.customAddressButtons = true
        var controls = store.toolbar
        var values = left ? store.addressLeftActions : store.addressRightActions; operation(&values)
        if left { controls.left = values } else { controls.right = values }
        store.updateToolbar(controls); store.updatePresentation(p)
    }
}

@MainActor
struct HomeBackgroundImage: View {
    @ObservedObject var store: BrowserStore
    var body: some View {
        GeometryReader { geometry in
            if let image = store.homeBackground {
                let placement = BackgroundPlacement.calculate(imageWidth: image.size.width, imageHeight: image.size.height,
                                                               viewportWidth: geometry.size.width, viewportHeight: geometry.size.height, preferences: store.presentation)
                Image(uiImage: image).resizable().frame(width: placement.width, height: placement.height)
                    .position(x: placement.x, y: placement.y)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

@MainActor
struct BackgroundAdjustmentView: View {
    @ObservedObject var store: BrowserStore
    @State private var landscapePreview = false
    var body: some View {
        Form {
            Section("プレビュー") {
                Picker("向き", selection: $landscapePreview) { Text("縦").tag(false); Text("横").tag(true) }.pickerStyle(.segmented)
                GeometryReader { geometry in
                    let aspect = landscapePreview ? 2.0 : 0.58
                    let width = min(geometry.size.width, 240 * aspect)
                    HomeBackgroundImage(store: store).frame(width: width, height: width / aspect)
                        .background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: 240)
                if store.homeBackground == nil { Text("ブラウザ機能から背景画像を選んでください。").foregroundStyle(.secondary) }
            }
            Section("表示する範囲") {
                Text("ズーム：\(Int(store.presentation.backgroundZoom * 100))％")
                Slider(value: preference(\.backgroundZoom), in: 1...3, step: 0.05).accessibilityIdentifier("backgroundZoomSlider")
                Text("左右の位置")
                Slider(value: preference(\.backgroundHorizontalOffset), in: -1...1).accessibilityIdentifier("backgroundHorizontalSlider")
                Text("上下の位置")
                Slider(value: preference(\.backgroundVerticalOffset), in: -1...1).accessibilityIdentifier("backgroundVerticalSlider")
                Button("中央・全体に戻す") {
                    var p = store.presentation; p.backgroundZoom = 1; p.backgroundHorizontalOffset = 0; p.backgroundVerticalOffset = 0; store.updatePresentation(p)
                }
            }
            Section { Text("元の画像を残したまま、画面に収まる範囲を変更します。縦横の画面サイズに合わせて切り抜き位置を計算します。") }
        }.navigationTitle("背景の位置・ズーム")
    }
    private func preference(_ path: WritableKeyPath<PresentationPreferences, Double>) -> Binding<Double> {
        Binding(get: { store.presentation[keyPath: path] }, set: { value in var p = store.presentation; p[keyPath: path] = value; store.updatePresentation(p) })
    }
}
