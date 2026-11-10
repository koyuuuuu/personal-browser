import Combine
import UIKit
import WebKit

struct PasswordFormTarget: Identifiable, Hashable {
    let tabID: UUID
    let epoch: UUID
    let documentID: String
    let formID: String
    let site: PasswordOrigin
    let isPasswordField: Bool
    let isMainFrame: Bool
    let eligibleForAutomaticFill: Bool
    let focused: Bool
    let currentPassword: Bool
    var id: String { tabID.uuidString + documentID + "/" + formID }
}

struct PasswordSaveOffer: Identifiable {
    let id = UUID()
    let tabID: UUID
    let record: PasswordRecord
    let passwordChange: Bool
    let expiresAt = Date().addingTimeInterval(120)
}

@MainActor
final class PasswordFormController: ObservableObject {
    static let shared = PasswordFormController()
    @Published private(set) var forms: [PasswordFormTarget] = []
    @Published private(set) var saveOffer: PasswordSaveOffer?
    private var observers: [AnyCancellable] = []
    private init() {
        for name in [UIApplication.didEnterBackgroundNotification, .passwordVaultDidLock] {
            observers.append(NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissSaveOffer() }
            })
        }
    }
    private var interfaceAvailable = true
    func setInterfaceAvailable(_ value: Bool) {
        interfaceAvailable = value
        if !value { dismissSaveOffer() }
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private final class Entry {
        weak var view: WKWebView?
        let tabID: UUID
        let isPrivate: Bool
        let trusted: () -> Bool
        let found: (Bool) -> Void
        var automaticAttempts = Set<String>()
        var epoch = UUID()
        var frames: [String: WKFrameInfo] = [:]
        var targets: [String: [PasswordFormTarget]] = [:]
        init(_ view: WKWebView, tabID: UUID, isPrivate: Bool, trusted: @escaping () -> Bool, found: @escaping (Bool) -> Void) {
            self.view=view; self.tabID=tabID; self.isPrivate=isPrivate; self.trusted=trusted; self.found=found
        }
    }
    func attach(_ view: WKWebView, tabID: UUID, isPrivate: Bool, trusted: @escaping () -> Bool, found: @escaping (Bool) -> Void) {
        entries[ObjectIdentifier(view)] = Entry(view, tabID: tabID, isPrivate: isPrivate, trusted: trusted, found: found)
        let controller=view.configuration.userContentController
        controller.add(PasswordFormHandler(owner: self), contentWorld: .defaultClient, name: "browserPasswords")
        let hints = PasswordVault.shared.improveAppleAutoFill ? "true" : "false"
        let offers = PasswordVault.shared.offerToSave ? "true" : "false"
        controller.addUserScript(WKUserScript(source: "globalThis.__personalBrowserAppleHints = " + hints + ";\nglobalThis.__personalBrowserSaveOffers = " + offers + ";\n" + PasswordFormScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }
    func reset(_ view: WKWebView) {
        guard let entry=entries[ObjectIdentifier(view)] else{return}
        entry.epoch=UUID();entry.automaticAttempts.removeAll();entry.frames.removeAll();entry.targets.removeAll();entry.found(false);publish()
    }
    func detach(_ view: WKWebView) {
        if let tabID = entries[ObjectIdentifier(view)]?.tabID, saveOffer?.tabID == tabID { dismissSaveOffer() }
        entries.removeValue(forKey:ObjectIdentifier(view))?.found(false)
        view.configuration.userContentController.removeScriptMessageHandler(forName:"browserPasswords",contentWorld:.defaultClient);publish()
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let view=message.webView, let entry=entries[ObjectIdentifier(view)],
              let url=view.url, let top=try? PasswordOrigin(url),
              let frameURL=message.frameInfo.request.url, let frame=try? PasswordOrigin(frameURL), top==frame,
              let body=message.body as? [String:Any], let doc=body["doc"] as? String, !doc.isEmpty, doc.count<128 else{return}
        if body["kind"] as? String == "save" {
            guard interfaceAvailable, PasswordVault.shared.offerToSave, !entry.isPrivate, entry.trusted(), message.frameInfo.isMainFrame,
                  let id = body["form"] as? String,
                  entry.targets[doc]?.contains(where: { $0.formID == id && $0.isPasswordField }) == true,
                  let user = body["username"] as? String, let password = body["password"] as? String,
                  let change = body["passwordChange"] as? Bool,
                  let record = try? PasswordRecord(site: top, username: user, password: password).validated() else { return }
            if let current = saveOffer, current.tabID == entry.tabID,
               current.record.accountKey == record.accountKey, current.record.password.utf8.elementsEqual(record.password.utf8) { return }
            if PasswordVault.shared.unlocked,
               (try? PasswordSavePolicy.proposal(record, records: PasswordVault.shared.records, passwordChange: change)) == .unchanged { return }
            let offer = PasswordSaveOffer(tabID: entry.tabID, record: record, passwordChange: change)
            saveOffer = offer
            let id = offer.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                if self?.saveOffer?.id == id { self?.dismissSaveOffer() }
            }
            return
        }
        guard let values=body["forms"] as? [[String:Any]], values.count<=16,
              entry.frames[doc] != nil || entry.frames.count<32 else{return}
        entry.frames[doc]=message.frameInfo
        var seen=Set<String>()
        entry.targets[doc]=values.compactMap { item in
            guard let id=item["id"] as? String,!id.isEmpty,id.count<=32,seen.insert(id).inserted,
                  let current=item["current"] as? Bool else{return nil}
            return PasswordFormTarget(tabID:entry.tabID,epoch:entry.epoch,documentID:doc,formID:id,site:top,
                isPasswordField:item["passwordField"] as? Bool ?? true,isMainFrame:message.frameInfo.isMainFrame, eligibleForAutomaticFill:item["automatic"] as? Bool ?? false,
                focused:item["focused"] as? Bool ?? false,currentPassword:current)
        }
        entry.found(entry.targets.values.contains { !$0.isEmpty });publish()
    }
    private func publish() {
        // Passive form metadata never includes field values. Submission offers use
        // the separate, bounded save branch above and stay only in memory.
        let next=entries.values.flatMap { $0.targets.values.flatMap { $0 } }.sorted { $0.id<$1.id }
        if next != forms { forms=next }
    }
    func targets(for tab: BrowserTab?) -> [PasswordFormTarget] { forms.filter { $0.tabID==tab?.id } }
    private func checked(_ target: PasswordFormTarget, capture: Bool, systemFocus: Bool = false, management: Bool = false) throws -> (Entry,WKWebView,WKFrameInfo) {
        guard let entry=entries.values.first(where:{$0.tabID==target.tabID}),entry.epoch==target.epoch,
              let view=entry.view, let frame=entry.frames[target.documentID],
              entry.targets[target.documentID]?.contains(where:{$0.id==target.id})==true,
              let url=view.url, let top=try? PasswordOrigin(url),
              let frameURL=frame.request.url, let origin=try? PasswordOrigin(frameURL),top==origin,top==target.site,
              (interfaceAvailable || management), UIApplication.shared.applicationState == .active, entry.trusted(),
              systemFocus || !entry.isPrivate || (!capture && PasswordVault.shared.allowPrivateFill) else {throw PasswordVaultError.invalidSite}
        if !capture && !systemFocus && !management {
            let focused = entry.targets.values.flatMap { $0 }.filter(\.focused)
            guard focused.isEmpty || (focused.count == 1 && focused.first?.id == target.id) else { throw PasswordVaultError.invalidSite }
        }
        return(entry,view,frame)
    }
    private func command(_ target: PasswordFormTarget, action: String, username: String? = nil, password: String? = nil, automatic: Bool = false, management: Bool = false) async throws -> [String:Any] {
        if action != "focus" { try PasswordVault.shared.requireUnlocked() }
        let (_,view,frame)=try checked(target,capture:action=="capture",systemFocus:action=="focus",management:management)
        if action == "focus" { view.becomeFirstResponder() }
        var args:[String:Any] = ["action":action,"doc":target.documentID,"form":target.formID,"automatic":automatic]
        if let username {args["username"]=username}; if let password, target.isPasswordField {args["password"]=password}
        let result: [String:Any] = try await withCheckedThrowingContinuation { continuation in
            runPasswordCommand(view,frame:frame,command:args) { value,error in
                // Never log/evaluate an error description containing page data.
                guard error==nil, let object=value as? [String:Any], object["ok"] as? Bool==true else {
                    continuation.resume(throwing:PasswordVaultError.invalidSite);return
                }
                continuation.resume(returning:object)
            }
        }
        _ = try checked(target,capture:action=="capture",systemFocus:action=="focus",management:management)
        return result
    }
    func fill(_ record: PasswordRecord, into target: PasswordFormTarget, fromManager: Bool = false) async throws {
        guard PasswordVault.shared.unlocked,record.site==target.site,target.currentPassword else {throw PasswordVaultError.locked}
        _ = try await command(target,action:"fill",username:record.username,password:record.password,management:fromManager)
    }
    func focusForAppleAutoFill(_ target: PasswordFormTarget) async throws {
        _ = try await command(target,action:"focus")
    }
    func dismissKeyboard(for tabID: UUID) {
        entries.values.first(where: { $0.tabID == tabID })?.view?.endEditing(true)
    }
    func setAppleHints(_ enabled: Bool) {
        for entry in entries.values {
            guard let view=entry.view else { continue }
            // Update future documents too, without touching other modules'
            // user scripts or recreating the mounted WebView.
            let content=view.configuration.userContentController
            let scripts=content.userScripts
            content.removeAllUserScripts()
            for script in scripts {
                if script.source.hasPrefix("globalThis.__personalBrowserAppleHints = ") {
                    let flag=enabled ? "true" : "false"
                    let offers=PasswordVault.shared.offerToSave ? "true" : "false"
                    content.addUserScript(WKUserScript(source:"globalThis.__personalBrowserAppleHints = " + flag + ";\nglobalThis.__personalBrowserSaveOffers = " + offers + ";\n" + PasswordFormScript.source,
                        injectionTime:.atDocumentStart,forMainFrameOnly:false,in:.defaultClient))
                } else { content.addUserScript(script) }
            }
            setPasswordAppleHints(view,frame:nil,enabled:enabled)
            for frame in entry.frames.values where !frame.isMainFrame {
                setPasswordAppleHints(view,frame:frame,enabled:enabled)
            }
        }
    }
    func dismissSaveOffer() { saveOffer = nil }
    func keepSaveOffer(for tab: BrowserTab?) {
        guard let offer = saveOffer else { return }
        guard let tab, tab.id == offer.tabID, !tab.isPrivate, let url = tab.url,
              (try? PasswordOrigin(url)) == offer.record.site, Date() < offer.expiresAt else { dismissSaveOffer(); return }
    }
    func acceptSaveOffer(_ id: UUID, tab: BrowserTab, accountID: UUID? = nil) throws {
        keepSaveOffer(for: tab)
        guard let offer = saveOffer, offer.id == id, tab.passwordPageTrusted else { throw PasswordVaultError.invalidSite }
        try PasswordVault.shared.requireUnlocked()
        let proposal = try PasswordSavePolicy.proposal(offer.record, records: PasswordVault.shared.records,
            passwordChange: offer.passwordChange, accountID: accountID)
        switch proposal {
        case .insert(let value), .update(let value): try PasswordVault.shared.save(value)
        case .unchanged: break
        case .chooseAccount: throw PasswordVaultError.invalidRecord
        }
        dismissSaveOffer()
    }
    func setSaveOffers(_ enabled: Bool) {
        if !enabled { dismissSaveOffer() }
        for entry in entries.values {
            guard let view = entry.view else { continue }
            setPasswordSaveOffers(view, enabled: enabled)
        }
        // Rebuild only this module's scripts for future documents too.
        setAppleHints(PasswordVault.shared.improveAppleAutoFill)
    }
    func fillAutomatically(_ record: PasswordRecord, into target: PasswordFormTarget) async throws {
        guard let entry=entries.values.first(where:{$0.tabID==target.tabID}),
              PasswordAutomaticFillPolicy.candidate(records:PasswordVault.shared.records,site:target.site,
                enabled:PasswordVault.shared.automaticallyFill,unlocked:PasswordVault.shared.unlocked,
                isPrivate:entry.isPrivate,formCount:targets(forID:target.tabID).filter(\.currentPassword).count,
                isMainFrame:target.isMainFrame,eligible:target.eligibleForAutomaticFill)?.id==record.id,
              entry.automaticAttempts.insert(target.id).inserted else { return }
        _ = try await command(target,action:"fill",username:record.username,password:record.password,automatic:true)
    }
    func targets(forID tabID: UUID) -> [PasswordFormTarget] { forms.filter { $0.tabID==tabID } }
    func capture(_ target: PasswordFormTarget) async throws -> PasswordRecord {
        guard PasswordVault.shared.unlocked, target.isPasswordField else {throw PasswordVaultError.locked}
        let result=try await command(target,action:"capture",management:true)
        guard PasswordVault.shared.unlocked,let user=result["username"] as? String,let password=result["password"] as? String else {throw PasswordVaultError.locked}
        return try PasswordRecord(site:target.site,username:user,password:password).validated()
    }
}

@MainActor
private final class PasswordFormHandler: NSObject,WKScriptMessageHandler {
    weak var owner:PasswordFormController?
    init(owner:PasswordFormController){self.owner=owner}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){owner?.receive(message)}
}
