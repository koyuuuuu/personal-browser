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

@MainActor
final class PasswordFormController: ObservableObject {
    static let shared = PasswordFormController()
    @Published private(set) var forms: [PasswordFormTarget] = []
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
        controller.addUserScript(WKUserScript(source: "globalThis.__personalBrowserAppleHints = " + hints + ";\n" + PasswordFormScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }
    func reset(_ view: WKWebView) {
        guard let entry=entries[ObjectIdentifier(view)] else{return}
        entry.epoch=UUID();entry.automaticAttempts.removeAll();entry.frames.removeAll();entry.targets.removeAll();entry.found(false);publish()
    }
    func detach(_ view: WKWebView) {
        entries.removeValue(forKey:ObjectIdentifier(view))?.found(false)
        view.configuration.userContentController.removeScriptMessageHandler(forName:"browserPasswords",contentWorld:.defaultClient);publish()
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let view=message.webView, let entry=entries[ObjectIdentifier(view)],
              let url=view.url, let top=try? PasswordOrigin(url),
              let frameURL=message.frameInfo.request.url, let frame=try? PasswordOrigin(frameURL), top==frame,
              let body=message.body as? [String:Any], let doc=body["doc"] as? String, !doc.isEmpty, doc.count<128,
              let values=body["forms"] as? [[String:Any]], values.count<=16,
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
        // No usernames/passwords/field labels/URLs are collected by this channel.
        let next=entries.values.flatMap { $0.targets.values.flatMap { $0 } }.sorted { $0.id<$1.id }
        if next != forms { forms=next }
    }
    func targets(for tab: BrowserTab?) -> [PasswordFormTarget] { forms.filter { $0.tabID==tab?.id } }
    private func checked(_ target: PasswordFormTarget, capture: Bool, systemFocus: Bool = false) throws -> (Entry,WKWebView,WKFrameInfo) {
        guard let entry=entries.values.first(where:{$0.tabID==target.tabID}),entry.epoch==target.epoch,
              let view=entry.view, let frame=entry.frames[target.documentID],
              entry.targets[target.documentID]?.contains(where:{$0.id==target.id})==true,
              let url=view.url, let top=try? PasswordOrigin(url),
              let frameURL=frame.request.url, let origin=try? PasswordOrigin(frameURL),top==origin,top==target.site,
              UIApplication.shared.applicationState == .active, entry.trusted(),
              systemFocus || !entry.isPrivate || (!capture && PasswordVault.shared.allowPrivateFill) else {throw PasswordVaultError.invalidSite}
        return(entry,view,frame)
    }
    private func command(_ target: PasswordFormTarget, action: String, username: String? = nil, password: String? = nil, automatic: Bool = false) async throws -> [String:Any] {
        if action != "focus" { try PasswordVault.shared.requireUnlocked() }
        let (_,view,frame)=try checked(target,capture:action=="capture",systemFocus:action=="focus")
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
        _ = try checked(target,capture:action=="capture",systemFocus:action=="focus")
        return result
    }
    func fill(_ record: PasswordRecord, into target: PasswordFormTarget) async throws {
        guard PasswordVault.shared.unlocked,record.site==target.site,target.currentPassword else {throw PasswordVaultError.locked}
        _ = try await command(target,action:"fill",username:record.username,password:record.password)
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
                    content.addUserScript(WKUserScript(source:"globalThis.__personalBrowserAppleHints = " + flag + ";\n" + PasswordFormScript.source,
                        injectionTime:.atDocumentStart,forMainFrameOnly:false,in:.defaultClient))
                } else { content.addUserScript(script) }
            }
            setPasswordAppleHints(view,frame:nil,enabled:enabled)
            for frame in entry.frames.values where !frame.isMainFrame {
                setPasswordAppleHints(view,frame:frame,enabled:enabled)
            }
        }
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
        let result=try await command(target,action:"capture")
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
